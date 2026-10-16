"""Phase 5 : actualisation manuelle d'un contexte WhatsApp.

L'utilisateur colle la suite de sa conversation (réponse reçue, message
qu'il a envoyé) sans réimporter l'export. Les messages rejoignent le
contexte existant (`context_messages`, rangs suivants) avec leur
PROVENANCE : `manual_received` / `manual_sent` — une information fournie
par l'utilisateur, jamais une réception vérifiée sur WhatsApp. Les messages
d'un export restent intouchables (filtre ici, déclencheur en base).

  - auteur : reçu → un participant autre que l'utilisateur (le contact par
    défaut ; obligatoire et vérifié dans un groupe) ; envoyé → l'utilisateur
    confirmé (« Vous êtes ») — jamais deviné ;
  - doublons : un message identique parmi les derniers du contexte, ou une
    proposition déjà déclarée envoyée (phase 4) → 409 `correspondances`,
    rien n'est écrit tant que l'utilisateur n'a pas confirmé ; confirmé, un
    envoyé identique à une déclaration y est relié
    (`declared_proposition_id`) : la mémoire ne le compte pas deux fois ;
  - écriture : une seule fonction SQL (atomique, verrou du contexte,
    idempotente par identifiant) ; le cache des messages (Redis) est vidé :
    la question suivante voit le contexte à jour. Aucun appel à l'IA.
"""

import logging
from dataclasses import dataclass
from datetime import datetime, timezone

import httpx
from redis.asyncio import Redis
from redis.exceptions import RedisError

from .comprehension import propositions as aide
from .comprehension.moteur import cle_cache
from .comprehension.reperes import normaliser
from .contextes import BaseIndisponible, ContexteIntrouvable, ErreurContexte
from .contextes_modeles import AddMessagesRequest, ContextMessageOut, UpdateManualMessage
from .supabase_client import SupabaseAdmin

logger = logging.getLogger(__name__)
DERNIERS_COMPARES = 200


class AuteurInvalide(ErreurContexte):
    """Auteur absent, inconnu du contexte, ou utilisateur non confirmé."""

    def __init__(self, detail: str) -> None:
        super().__init__(detail)
        self.detail = detail


class MessageOriginal(ErreurContexte):
    """Message d'un export : ni modifiable ni supprimable un par un."""


class MessageIntrouvable(ErreurContexte):
    pass


@dataclass
class Correspondances(Exception):
    items: list[dict]


def _participants(ctx: dict) -> list[str]:
    return [p for p in (ctx.get("participants") or []) if isinstance(p, str) and p.strip()]


def auteur_pour(ctx: dict, direction: str, auteur: str | None) -> str:
    """Auteur VÉRIFIÉ d'un message collé (jamais une supposition)."""
    moi = ctx.get("current_user_name")
    if direction == "sent":
        if not moi:
            raise AuteurInvalide("Indiquez d'abord qui vous êtes dans cette conversation.")
        return moi
    autres = [p for p in _participants(ctx) if p != moi]
    if auteur:
        if auteur == moi:
            raise AuteurInvalide("Un message reçu ne peut pas venir de vous.")
        if auteur not in autres and auteur != ctx.get("contact_name"):
            raise AuteurInvalide("Cet auteur ne fait pas partie de la conversation.")
        return auteur
    if ctx.get("is_group"):
        raise AuteurInvalide("Dans un groupe, choisissez l'auteur du message.")
    return autres[0] if len(autres) == 1 else ctx["contact_name"]


@dataclass
class AjoutsManuels:
    supabase: SupabaseAdmin
    redis: Redis

    async def _contexte(self, user_id: str, context_id: str) -> dict:
        ctx = await self.supabase.get_context(context_id, user_id)
        if ctx is None:
            raise ContexteIntrouvable()
        return ctx

    async def _vider_cache(self, context_id: str) -> None:
        try:
            await self.redis.delete(cle_cache(context_id))
        except RedisError:
            logger.warning("Cache d'un contexte non vidé", exc_info=True)

    async def ajouter(self, user_id: str, context_id: str, demande: AddMessagesRequest) -> list[ContextMessageOut]:
        try:
            ctx = await self._contexte(user_id, context_id)
            lignes = [
                {"id": str(m.id), "origin": "manual_received" if m.direction == "received" else "manual_sent",
                 "author": auteur_pour(ctx, m.direction, m.author), "content": m.content.strip(),
                 "sent_at": m.sent_at.isoformat() if m.sent_at else None, "sent_at_raw": m.sent_at_raw}
                for m in demande.messages
            ]
            correspondances = await self._correspondances(user_id, ctx, lignes)
            if correspondances and not demande.confirm_duplicates:
                raise Correspondances(correspondances)
            for c in correspondances:
                if c["type"] == "declaration":
                    lignes[c["index"]]["declared_proposition_id"] = c["proposition_id"]
            resultat = await self.supabase.add_context_messages(user_id, context_id, lignes)
        except httpx.HTTPStatusError as exc:
            if "JVC11" in exc.response.text:
                raise ContexteIntrouvable() from None
            logger.error("Ajout manuel refusé par la base", exc_info=True)
            raise BaseIndisponible() from None
        except httpx.HTTPError:
            logger.error("Supabase indisponible (ajout manuel)", exc_info=True)
            raise BaseIndisponible() from None
        await self._vider_cache(context_id)
        # Volumes seulement : jamais le contenu.
        logger.info("Ajout manuel : %d message(s) au contexte", len(resultat))
        return [ContextMessageOut.model_validate(r) for r in resultat]

    async def _correspondances(self, user_id: str, ctx: dict, lignes: list[dict]) -> list[dict]:
        """Doublons possibles : messages identiques (même auteur) parmi les
        derniers du contexte, et propositions déclarées envoyées."""
        derniers = await self.supabase.list_last_context_messages(ctx["id"], user_id, DERNIERS_COMPARES)
        connus = {(m.get("author"), normaliser(m.get("content") or "")): m for m in derniers}
        declarations = []
        if any(l["origin"] == "manual_sent" for l in lignes):
            for l in await self.supabase.list_declared_replies(user_id):
                declarations.extend(
                    d for d in aide.declarations(l.get("attachments"))
                    if d.get("statut") == "declaree_envoyee" and d.get("context_id") == ctx["id"])
        trouves: list[dict] = []
        for i, l in enumerate(lignes):
            texte = normaliser(l["content"])
            m = connus.get((l["author"], texte))
            if m is not None and str(m.get("id")) != l["id"]:
                trouves.append({"index": i, "type": "message", "message_order": m["message_order"],
                                "origin": m.get("origin", "export"), "texte": m.get("content"),
                                "sent_at": m.get("sent_at")})
            if l["origin"] == "manual_sent":
                d = next((d for d in declarations if normaliser(str(d.get("texte") or "")) == texte), None)
                if d is not None:
                    trouves.append({"index": i, "type": "declaration", "proposition_id": d["proposition_id"],
                                    "texte": d.get("texte"), "declared_at": d.get("declared_at"),
                                    "ton": d.get("ton")})
        return trouves

    async def modifier(self, user_id: str, context_id: str, message_id: str,
                       demande: UpdateManualMessage) -> ContextMessageOut:
        try:
            ctx = await self._contexte(user_id, context_id)
            m = await self.supabase.get_context_message(message_id, context_id, user_id)
            if m is None:
                raise MessageIntrouvable()
            if m.get("origin", "export") == "export":
                raise MessageOriginal()
            champs: dict = {}
            if demande.content is not None:
                champs["content"] = demande.content.strip()
            if demande.author is not None:
                direction = "received" if m["origin"] == "manual_received" else "sent"
                champs["author"] = auteur_pour(ctx, direction, demande.author)
            if demande.clear_date:
                champs["sent_at"], champs["sent_at_raw"] = None, ""
            elif demande.sent_at is not None:
                champs["sent_at"] = demande.sent_at.isoformat()
                champs["sent_at_raw"] = demande.sent_at_raw or ""
            champs["edited_at"] = datetime.now(timezone.utc).isoformat()
            lignes = await self.supabase.update_manual_message(message_id, context_id, user_id, champs)
        except httpx.HTTPError:
            logger.error("Supabase indisponible (correction d'un ajout)", exc_info=True)
            raise BaseIndisponible() from None
        if not lignes:
            raise MessageIntrouvable()
        await self._vider_cache(context_id)
        return ContextMessageOut.model_validate(lignes[0])

    async def supprimer(self, user_id: str, context_id: str, message_id: str) -> None:
        try:
            await self._contexte(user_id, context_id)
            m = await self.supabase.get_context_message(message_id, context_id, user_id)
            if m is None:
                raise MessageIntrouvable()
            if m.get("origin", "export") == "export":
                raise MessageOriginal()
            supprime = await self.supabase.delete_manual_message(message_id, context_id, user_id)
        except httpx.HTTPError:
            logger.error("Supabase indisponible (suppression d'un ajout)", exc_info=True)
            raise BaseIndisponible() from None
        if not supprime:
            raise MessageIntrouvable()
        await self._vider_cache(context_id)
