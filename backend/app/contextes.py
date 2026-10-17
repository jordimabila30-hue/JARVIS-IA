"""Contextes WhatsApp joints aux conversations JARVIS (logique métier).

Une pièce jointe WhatsApp (messages sélectionnés dans l'application) est
enregistrée avec la consigne qui l'accompagne :

  conversation JARVIS ──< message `user` (consigne)
          │                      │
          └──< conversation_contexts (message_id → consigne)
                     └──< context_messages (sélection, rangs 0..n-1)

Règles :
  - le compte vient TOUJOURS du JWT vérifié (paramètre `user_id`), jamais du
    corps de la requête ; la clé service_role contourne la RLS, donc chaque
    lecture et suppression filtre explicitement par ce compte ;
  - enregistrement en UNE transaction (fonction PostgreSQL
    `enregistrer_contexte_whatsapp`) : jamais de pièce jointe partielle ;
  - idempotence : `context_id` choisi par l'appareil ; un réessai renvoie
    l'enregistrement existant (complet, tout ou rien) ;
  - aucun appel à l'IA, aucun quota : ce n'est que du stockage ;
  - le contenu des messages n'est jamais journalisé.
"""

import logging
from dataclasses import dataclass

import httpx

from .config import Settings
from .contextes_modeles import (
    ContextMessagesPage,
    ContextOut,
    SaveContextRequest,
    SaveContextResponse,
)
from .supabase_client import SupabaseAdmin

logger = logging.getLogger(__name__)


class ErreurContexte(Exception):
    """Erreur métier, sans détail de la base (jamais exposé au client)."""


class ConversationIntrouvable(ErreurContexte):
    pass


class ContexteIntrouvable(ErreurContexte):
    pass


class IdentifiantDejaUtilise(ErreurContexte):
    pass


class DonneesInvalides(ErreurContexte):
    pass


class RequeteTropVolumineuse(ErreurContexte):
    pass


class BaseIndisponible(ErreurContexte):
    pass


# Codes levés par la fonction SQL (voir la migration).
_ERREURS_SQL = {
    "JVC01": ConversationIntrouvable,
    "JVC02": IdentifiantDejaUtilise,
    "JVC03": IdentifiantDejaUtilise,
    "JVC04": DonneesInvalides,
    "23514": DonneesInvalides,   # contrainte CHECK
    "22P02": DonneesInvalides,   # valeur mal formée
    "23503": ConversationIntrouvable,
}


def _code_postgrest(exc: httpx.HTTPStatusError) -> str | None:
    try:
        return exc.response.json().get("code")
    except ValueError:
        return None


@dataclass
class ContextesService:
    supabase: SupabaseAdmin
    settings: Settings

    # --- Enregistrement --------------------------------------------------

    def verifier_volume(self, demande: SaveContextRequest) -> None:
        s = self.settings
        if len(demande.messages) > s.whatsapp_context_max_messages:
            raise RequeteTropVolumineuse()
        if sum(len(m.content) for m in demande.messages) > s.whatsapp_context_max_chars:
            raise RequeteTropVolumineuse()

    async def enregistrer(self, user_id: str, demande: SaveContextRequest) -> SaveContextResponse:
        self.verifier_volume(demande)
        messages = sorted(demande.messages, key=lambda m: m.message_order)
        dates = [m.sent_at for m in messages if m.sent_at is not None]
        contexte = demande.context.model_dump(mode="json")
        # Période réelle des messages choisis (jamais inventée).
        contexte["period_start"] = min(dates).isoformat() if dates else None
        contexte["period_end"] = max(dates).isoformat() if dates else None
        params = {
            "p_user_id": user_id,
            "p_context_id": str(demande.context_id),
            "p_message_id": str(demande.message_id),
            "p_conversation_id": (
                None if demande.conversation_id is None else str(demande.conversation_id)
            ),
            "p_consigne": demande.instruction,
            "p_contexte": contexte,
            "p_messages": [m.model_dump(mode="json") for m in messages],
        }
        try:
            resultat = await self.supabase.save_whatsapp_context(
                params, timeout=self.settings.whatsapp_context_timeout
            )
        except httpx.HTTPStatusError as exc:
            code = _code_postgrest(exc)
            if code == "23505":
                # Deux envois simultanés de la même pièce jointe : le premier
                # a gagné (transaction complète) ; on renvoie son résultat.
                return await self._deja_enregistre(user_id, demande)
            erreur = _ERREURS_SQL.get(code or "")
            if erreur is not None:
                raise erreur() from None
            logger.error("Enregistrement d'un contexte refusé par Supabase (code %s)", code)
            raise BaseIndisponible() from None
        except httpx.HTTPError:
            # Délai dépassé ou réseau : la transaction a pu aboutir ou non ;
            # l'appareil réessaie avec le même context_id (sans risque).
            logger.error("Supabase indisponible pour un contexte WhatsApp", exc_info=True)
            raise BaseIndisponible() from None
        return SaveContextResponse.model_validate(resultat)

    async def _deja_enregistre(
        self, user_id: str, demande: SaveContextRequest
    ) -> SaveContextResponse:
        try:
            existant = await self.supabase.get_context(str(demande.context_id), user_id)
        except httpx.HTTPError:
            raise BaseIndisponible() from None
        if existant is None:
            raise IdentifiantDejaUtilise()
        return SaveContextResponse(
            conversation_id=existant["conversation_id"],
            message_id=existant["message_id"],
            context_id=existant["id"],
            messages_count=_nombre(existant),
            conversation_created=False,
            already_saved=True,
        )

    # --- Lecture -----------------------------------------------------------

    async def lister(self, user_id: str, conversation_id: str) -> list[ContextOut]:
        try:
            if await self.supabase.get_conversation(conversation_id, user_id) is None:
                raise ConversationIntrouvable()
            lignes = await self.supabase.list_contexts(conversation_id, user_id)
        except httpx.HTTPError:
            logger.error("Supabase indisponible (liste des contextes)", exc_info=True)
            raise BaseIndisponible() from None
        return [_contexte(l) for l in lignes]

    async def obtenir(self, user_id: str, context_id: str) -> ContextOut:
        try:
            ligne = await self.supabase.get_context(context_id, user_id)
        except httpx.HTTPError:
            logger.error("Supabase indisponible (contexte)", exc_info=True)
            raise BaseIndisponible() from None
        if ligne is None:
            raise ContexteIntrouvable()
        return _contexte(ligne)

    async def messages(
        self, user_id: str, context_id: str, *, after: int, limit: int, manuels: bool = False
    ) -> ContextMessagesPage:
        limit = max(1, min(limit, self.settings.whatsapp_context_page_max))
        try:
            # Le contexte d'un autre compte n'existe pas pour celui-ci.
            if await self.supabase.get_context(context_id, user_id) is None:
                raise ContexteIntrouvable()
            # Un de plus : savoir s'il reste une page, sans compter.
            lignes = await self.supabase.list_context_messages(
                context_id, user_id, after=after, limit=limit + 1,
                **({"manuels": True} if manuels else {}),
            )
        except httpx.HTTPError:
            logger.error("Supabase indisponible (messages d'un contexte)", exc_info=True)
            raise BaseIndisponible() from None
        page = lignes[:limit]
        suite = len(lignes) > limit
        return ContextMessagesPage(
            context_id=context_id,
            messages=page,
            next_after=page[-1]["message_order"] if suite and page else None,
        )

    # --- Suppression -------------------------------------------------------

    async def supprimer(self, user_id: str, context_id: str) -> None:
        """Supprime la pièce jointe et ses messages (cascade), rien d'autre :
        ni la conversation, ni la consigne, ni les autres contextes."""
        try:
            supprime = await self.supabase.delete_context(context_id, user_id)
        except httpx.HTTPError:
            logger.error("Supabase indisponible (suppression d'un contexte)", exc_info=True)
            raise BaseIndisponible() from None
        if not supprime:
            raise ContexteIntrouvable()


def _nombre(ligne: dict) -> int:
    embarque = ligne.get("context_messages") or [{"count": 0}]
    return int(embarque[0].get("count", 0))


def _contexte(ligne: dict) -> ContextOut:
    return ContextOut.model_validate({**ligne, "messages_count": _nombre(ligne)})
