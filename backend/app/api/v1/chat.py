"""Chat en streaming SSE, par MIA universel (app/llm/ : Claude par défaut).

POST /api/v1/chat/stream   (Authorization: Bearer <jwt Supabase>)
  corps : {"message": "...", "conversation_id": "<uuid>" | null, "ton": "naturel"}

L'authentification et le quota (401 / 403 / 404 / 429) sont contrôlés AVANT
l'ouverture du flux : ces erreurs arrivent en réponse HTTP JSON classique.
Ensuite, le flux `text/event-stream` émet :
  event: meta   {"conversation_id", "message_id", "quota"}   une fois, au début
  event: delta  {"text"}                                      fragments de réponse
  event: references {"message_id", "references", "note"}     (WhatsApp) avant done
  event: propositions {"message_id", "statut", "mode", "tons"} (WhatsApp) aide à répondre :
                     statut "complet" (toutes les combinaisons) ou
                     "incomplet" (quota / erreur : « Reprendre »)
  event: outil  {"nom", "etat", "code"}                       (ODO) état d'un outil :
                     en_cours | termine | erreur | refuse | confirmation
  event: confirmation {"id", "outil", "resume", "expire_at"}  (ODO) action sensible
                     préparée, à confirmer par POST /api/v1/odo/confirmations/{id}
  event: done   {"message_id", "usage", "quota"}              fin normale
  event: error  {"code", "message"}                           échec de génération,
                     refus du modèle (llm_refus) ou réponse coupée par
                     le plafond de sortie (llm_incomplet) : jamais `done`
                     pour une réponse interrompue

Fournisseur : MIA universel (`selection.fournisseur()`, LLM_PROVIDER,
Claude par défaut). Aucun basculement automatique. En-tête
`X-Jarvis-Fournisseur` (ex. « groq ») accepté SEULEMENT hors production,
LLM_SELECTION_MANUELLE activé et compte dans LLM_ADMINS (sinon 403).
La réflexion interne du modèle n'est jamais diffusée ; elle est comptée
dans les tokens de sortie (quota) et dans le plafond (marge ajoutée).

Fin de flux (normale, erreur ou déconnexion du client) : une tâche de fond
enregistre le message utilisateur et la réponse dans `messages`, comptabilise
les tokens et met à jour le contexte court Redis. Si aucun texte n'a été
généré, la requête est rendue au quota et rien n'est enregistré.

Conversations WhatsApp jointes (app/comprehension/) : si le chat en a,
  - `whatsapp_analysis` absent → 409 {"code": "consentement_requis"}, AVANT
    tout appel au fournisseur (et la requête est rendue au quota) ;
  - "allowed" → instructions du moteur de compréhension + extraits choisis
    selon la question, dans `COMPREHENSION_BUDGET_TOKENS` ;
  - "declined" → aucun contenu WhatsApp, le modèle sait qu'il n'y a pas accès.
  `reply_to` (UUID d'une consigne déjà enregistrée avec sa pièce jointe) :
  la consigne devient la question sans être réinsérée.
Limite de débit du fournisseur (429) : attente conseillée (au plus
`LLM_RATE_LIMIT_MAX_WAIT` s), flux ouvert grâce à des commentaires SSE.

ODO (outils, ODO_ACTIF, désactivé par défaut) : seulement pour un chat
ordinaire (ni pièce jointe WhatsApp, ni consigne) et si des outils sont
autorisés pour le compte ; sinon, flux strictement inchangé. Plusieurs tours
du modèle → UN message compté, tokens additionnés, budget revérifié entre
les tours. Les anciennes applications ignorent `outil` et `confirmation`.

Contexte court (Redis) :
  ctx:{conversation_id}   liste JSON {role, content}, N derniers messages, TTL 1 h
  Absent -> rechargé depuis Supabase (`messages`).
"""

import asyncio
import json
import logging
import time
from dataclasses import replace
from datetime import datetime, timezone
from enum import Enum
from typing import Any, Literal
from uuid import UUID, uuid4

import httpx
from fastapi import APIRouter, Depends, HTTPException, Request, status
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field
from redis.asyncio import Redis
from redis.exceptions import RedisError

from ...auth import AuthUser, get_current_user
from ...llm import (
    ErreurFournisseur,
    ErreurLLM,
    Fin,
    FournisseurInconnu,
    FournisseurLLM,
    FournisseurNonConfigure,
    LimiteDebit,
    RaisonArret,
    RequeteTropGrande,
    Texte,
    Usage,
    selection,
)
from ...llm.base import MESSAGES as MESSAGES_LLM
from ...odo.contrat import DemandeConfirmation, EtatOutil
from ...odo.service import ServiceODO, get_odo
from ...comprehension.instructions import NOTE_PIECE_SUPPRIMEE
from ...comprehension import ciblage, generation, memoire, propositions as aide, reperes, restauration
from ...comprehension.attribution import CorrecteurAttributions
from ...comprehension.moteur import MoteurComprehension, Preparation, choisir
from ...comprehension.references import FiltreReperes, entree_stockee, verifier
from ...config import Settings, get_settings
from ...quota import QuotaReservation, QuotaService, enforce_quota, get_quota_service, quota_exceeded
from ...redis_client import get_redis
from ...supabase_client import SupabaseAdmin, UserLimits, get_supabase

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/chat", tags=["chat"])


# --- Ton & prompt system ----------------------------------------------------------

class Ton(str, Enum):
    naturel = "naturel"
    amical = "amical"
    professionnel = "professionnel"
    concis = "concis"
    pedagogue = "pedagogue"
    enthousiaste = "enthousiaste"


INSTRUCTIONS_TON: dict[Ton, str] = {
    Ton.naturel: "Exprime-toi de façon naturelle et fluide, comme dans une conversation ordinaire.",
    Ton.amical: "Adopte un ton chaleureux et amical, tutoie l'utilisateur, reste bienveillant.",
    Ton.professionnel: "Adopte un ton professionnel et posé, vouvoie l'utilisateur, structure tes réponses.",
    Ton.concis: "Sois bref : va droit au but, quelques phrases au maximum, sans préambule.",
    Ton.pedagogue: "Explique pas à pas, avec des exemples simples, en vérifiant les notions clés.",
    Ton.enthousiaste: "Montre de l'énergie et de l'enthousiasme, tout en restant précis.",
}

SYSTEM_PROMPT = """Tu es JARVIS, l'assistant personnel de l'utilisateur.
Tu réponds en français, sauf si l'utilisateur écrit dans une autre langue.
Tes réponses peuvent être lues à voix haute : évite les tableaux et le Markdown
lourd, privilégie des phrases claires.
Date du jour (UTC) : {date}.

Ton demandé : {ton}"""


def build_system_prompt(ton: Ton, persona: str | None, now: datetime) -> str:
    prompt = SYSTEM_PROMPT.format(date=now.date().isoformat(), ton=INSTRUCTIONS_TON[ton])
    if persona:
        prompt += f"\nPersona actif : {persona}"
    return prompt


# --- Modèles ----------------------------------------------------------------------

class ChatRequest(BaseModel):
    message: str = Field(min_length=1, max_length=8000)
    conversation_id: UUID | None = None
    ton: Ton = Ton.naturel
    # Réponse à une consigne DÉJÀ enregistrée (pièce jointe WhatsApp) : la
    # consigne n'est pas réinsérée, seule la réponse l'est.
    reply_to: UUID | None = None
    # Envoi des messages WhatsApp joints au fournisseur IA : accord de
    # l'utilisateur ("allowed"), refus ("declined"), ou inconnu (null).
    whatsapp_analysis: Literal["allowed", "declined"] | None = None
    # Ton affiché dans les dernières propositions de réponse (« pourquoi
    # la deuxième ? » vise ce ton).
    ton_propose: str | None = Field(default=None, max_length=40)
    # Longueur affichée (phase 5.1) : « la deuxième » = 2e proposition de
    # CE ton et de CETTE longueur.
    longueur_proposee: Literal["court", "moyen", "long"] | None = None
    # Réponse de JARVIS qui porte les propositions affichées : référence
    # EXPLICITE (vérifiée : ce compte, ce chat) pour « pourquoi la deuxième ? ».
    propositions_message_id: UUID | None = None


# --- Utilitaires --------------------------------------------------------------------

def sse(event: str, data: dict[str, Any]) -> bytes:
    # json.dumps échappe les retours à la ligne : `data` tient sur une ligne.
    return f"event: {event}\ndata: {json.dumps(data, ensure_ascii=False)}\n\n".encode()




def estimate_tokens(text: str) -> int:
    """Estimation grossière (~4 caractères par token) quand OpenAI ne renvoie
    pas l'usage (client déconnecté avant la fin)."""
    return max(1, len(text) // 4)


def conversation_title(message: str) -> str:
    title = " ".join(message.split())
    return title if len(title) <= 60 else title[:57].rstrip() + "…"


def context_key(conversation_id: str) -> str:
    return f"ctx:{conversation_id}"


def describe_llm_error(exc: Exception) -> dict[str, str]:
    """Événement `error` : code pour l'app + message pour l'utilisateur.

    Les adaptateurs de MIA universel (app/llm/) traduisent eux-mêmes les
    erreurs de leur fournisseur ([ErreurLLM] : llm_rate_limit, llm_credit,
    llm_daily_quota, llm_too_large, llm_model, llm_auth, llm_timeout,
    llm_refus…) ; toute autre exception devient llm_unavailable."""
    if isinstance(exc, ErreurLLM):
        return exc.evenement()
    return {"code": "llm_unavailable", "message": MESSAGES_LLM["llm_unavailable"]}


# --- Fournisseur (MIA universel) ------------------------------------------------

ENTETE_FOURNISSEUR = "X-Jarvis-Fournisseur"

ERREUR_CONFIGURATION = {"code": "llm_config", "message": "Le service IA est mal configuré."}


def selection_autorisee(user: AuthUser, settings: Settings) -> bool:
    """Choix manuel du fournisseur : tests et comparaisons, jamais en
    production, seulement pour les comptes listés dans LLM_ADMINS."""
    return selection.choix_manuel_possible(settings) and user.id in settings.llm_admins


def fournisseur_attendu(limites: UserLimits | None, settings: Settings) -> tuple[str, str | None]:
    """(fournisseur, modèle) qui servira ce compte : celui de son offre
    (plan_config) si ABONNEMENTS_ROUTAGE est actif, sinon LLM_PROVIDER pour tous.
    Seule source de cette règle (route de chat, « Reprendre », /me/quota)."""
    if settings.abonnements_routage:
        if limites is None or not limites.llm_provider:
            raise FournisseurNonConfigure("Offre sans fournisseur IA (plan_config).")
        return limites.llm_provider, limites.llm_model
    nom = selection.nom_configure(settings)
    return nom, selection.modele_configure(nom, settings)


async def get_fournisseur(
    request: Request,
    user: AuthUser = Depends(get_current_user),
    settings: Settings = Depends(get_settings),
    quota_service: QuotaService = Depends(get_quota_service),
) -> FournisseurLLM:
    """Fournisseur de la requête, d'après l'identité vérifiée (JWT) :
    l'offre du compte (routage par abonnement : Free → GroqCloud, Pro →
    Claude), ou LLM_PROVIDER si ce routage est désactivé. Le corps de la
    requête n'y joue aucun rôle ; l'en-tête n'est accepté que pour les tests
    autorisés. Aucun repli vers un autre fournisseur. Résolu AVANT la
    réservation du quota : un refus ici ne consomme rien."""
    demande = (request.headers.get(ENTETE_FOURNISSEUR) or "").strip()
    if demande and not selection_autorisee(user, settings):
        logger.warning("Choix manuel du fournisseur refusé (compte non autorisé ou production)")
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail={
            "code": "fournisseur_interdit",
            "message": "Le choix du fournisseur IA est réservé aux tests autorisés."})
    try:
        if demande:
            llm = selection.fournisseur(demande, settings)
        else:
            limites = await quota_service.get_limits(user.id) if settings.abonnements_routage else None
            nom, modele = fournisseur_attendu(limites, settings)
            llm = selection.fournisseur(nom, settings, modele) if limites else selection.fournisseur(None, settings)
    except FournisseurInconnu as exc:
        raise HTTPException(status.HTTP_400_BAD_REQUEST,
                            detail={"code": "fournisseur_inconnu", "message": str(exc)}) from None
    except FournisseurNonConfigure as exc:
        logger.error("%s", exc)          # nom de la variable seulement, jamais une valeur
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, detail=ERREUR_CONFIGURATION) from None
    if demande:
        logger.info("Fournisseur choisi manuellement : %s (%s)", llm.nom, llm.modele)
    return llm


def plafond(llm: FournisseurLLM, sortie: int, settings: Settings) -> int:
    """Plafond de sortie : la réflexion interne (Claude) y est comptée."""
    return sortie + settings.llm_reflexion_marge_tokens if llm.reflexion_dans_sortie else sortie



# Les tâches de fond sont référencées ici pour ne pas être collectées en cours
# de route, et pour pouvoir les attendre à l'arrêt du serveur.
_background_tasks: set[asyncio.Task] = set()


def _spawn(coro) -> None:
    task = asyncio.create_task(coro)
    _background_tasks.add(task)
    task.add_done_callback(_background_tasks.discard)


async def wait_background_tasks() -> None:
    if _background_tasks:
        await asyncio.gather(*_background_tasks, return_exceptions=True)


# --- Contexte court -------------------------------------------------------------

async def load_context(
    redis: Redis, supabase: SupabaseAdmin, conversation_id: str, settings: Settings
) -> list[dict]:
    key = context_key(conversation_id)
    try:
        cached = await redis.lrange(key, 0, -1)
    except RedisError:
        logger.warning("Redis indisponible pour le contexte", exc_info=True)
        cached = None
    if cached:
        return [json.loads(item) for item in cached]

    rows = await supabase.get_recent_messages(conversation_id, settings.chat_history_messages)
    history = [
        {"role": row["role"], "content": row["content"]}
        for row in rows
        if row["role"] in ("user", "assistant")
    ]
    if history:
        try:
            async with redis.pipeline(transaction=True) as pipe:
                pipe.rpush(key, *(json.dumps(m, ensure_ascii=False) for m in history))
                pipe.expire(key, settings.chat_context_ttl)
                await pipe.execute()
        except RedisError:
            logger.warning("Impossible de mettre en cache le contexte", exc_info=True)
    return history


async def append_context(
    redis: Redis, conversation_id: str, new_conversation: bool, messages: list[dict], settings: Settings
) -> None:
    key = context_key(conversation_id)
    # Si le cache a expiré, on ne le recrée pas avec 2 messages seulement :
    # le prochain appel le rechargera complet depuis Supabase.
    if not new_conversation and not await redis.exists(key):
        return
    async with redis.pipeline(transaction=True) as pipe:
        pipe.rpush(key, *(json.dumps(m, ensure_ascii=False) for m in messages))
        pipe.ltrim(key, -settings.chat_history_messages, -1)
        pipe.expire(key, settings.chat_context_ttl)
        await pipe.execute()


# --- Finalisation (tâche de fond) -------------------------------------------------

async def finalize_exchange(
    *,
    quota_service: QuotaService,
    supabase: SupabaseAdmin,
    redis: Redis,
    settings: Settings,
    reservation: QuotaReservation,
    conversation_id: str,
    new_conversation: bool,
    user_row: dict | None,
    assistant_id: str,
    text: str,
    prompt_tokens: int,
    completion_tokens: int,
    model: str,
    provider: str | None = None,
    attachments: list[dict] | None = None,
) -> None:
    """[user_row] None : la question est une consigne déjà enregistrée
    (pièce jointe) ; seule la réponse est insérée. [attachments] :
    références vérifiées, dans la même ligne que la réponse. [model] :
    modèle qui a réellement répondu (MIA)."""
    if not text:
        await quota_service.release(reservation)
        return

    assistant_row = {
        "id": assistant_id,
        "conversation_id": conversation_id,
        "user_id": reservation.user.id,
        "role": "assistant",
        "content": text,
        "model": model,
        "tokens_input": prompt_tokens,
        "tokens_output": completion_tokens,
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    if attachments:
        assistant_row["attachments"] = attachments
    rows = [assistant_row] if user_row is None else [user_row, assistant_row]
    try:
        t = time.perf_counter()
        await supabase.insert_messages(rows)
        logger.info("Durée : enregistrement Supabase %d ms", (time.perf_counter() - t) * 1000)
    except httpx.HTTPError:
        logger.error("Échec d'enregistrement des messages (conversation=%s)", conversation_id, exc_info=True)

    # Une seule comptabilisation (jour, session, suivi par fournisseur), lots
    # de propositions compris.
    await quota_service.record_usage(reservation, prompt_tokens + completion_tokens,
                                     tokens_input=prompt_tokens, tokens_output=completion_tokens,
                                     provider=provider, model=model)

    try:
        await append_context(
            redis,
            conversation_id,
            new_conversation,
            [{"role": r["role"], "content": r["content"]} for r in rows],
            settings,
        )
    except RedisError:
        logger.warning("Échec de mise à jour du contexte Redis", exc_info=True)


async def _finalize_safely(**kwargs) -> None:
    try:
        await finalize_exchange(**kwargs)
    except Exception:
        logger.exception("Erreur lors de la finalisation d'un échange")


# --- Attente du fournisseur (limite de débit) ---------------------------------

# Silence maximal du flux pendant que le modèle réfléchit avant d'écrire
# (gpt-oss raisonne parfois 20 à 40 s) : un commentaire SSE garde la
# connexion vivante (délai d'inactivité de l'application : 30 s).
SILENCE_MAX_FLUX = 10.0


async def _avec_battement(flux, intervalle: float = SILENCE_MAX_FLUX):
    """Les éléments de [flux], et None après chaque [intervalle] de silence
    (sans jamais annuler la lecture en cours)."""
    it = flux.__aiter__()
    suivant = asyncio.ensure_future(it.__anext__())
    try:
        while True:
            fini, _ = await asyncio.wait({suivant}, timeout=intervalle)
            if not fini:
                yield None
                continue
            try:
                element = suivant.result()
            except StopAsyncIteration:
                return
            suivant = asyncio.ensure_future(it.__anext__())
            yield element
    finally:
        if not suivant.done():
            suivant.cancel()


def appel_lot(llm: FournisseurLLM, settings: Settings) -> generation.Appel:
    """Une requête de lot de propositions (generation.py) par MIA : schéma
    JSON garanti si le fournisseur le permet (Claude), sinon mode JSON ou
    texte relu (GroqCloud) ; limite de débit → LimiteAtteinte (attente
    conseillée, None : inutile d'attendre)."""

    async def appeler(messages: list[dict], max_tokens: int, schema: dict | None = None) -> tuple[str, int, int]:
        try:
            r = await llm.json(messages, max_sortie=plafond(llm, max_tokens, settings), schema=schema,
                               effort=settings.llm_effort_propositions or None)
        except LimiteDebit as exc:
            raise generation.LimiteAtteinte(exc.attente) from None
        return r.texte, r.usage.entree_totale, r.usage.sortie

    return appeler


async def completer_ensemble(ensemble: "generation.Ensemble", ctx, *, question: str, analyse: str,
                             aujourd_hui, memoire_bloc: str | None, llm: FournisseurLLM, settings: Settings):
    """Complète [ensemble] par lots (battements None pendant les attentes)."""
    ensemble.registre = generation.registre(ctx)
    contexte, fournis = generation.brief(ctx, question=question, analyse=analyse,
                                         aujourd_hui=aujourd_hui, memoire=memoire_bloc)
    # Battement au moins toutes les SILENCE_MAX_FLUX secondes, même pendant
    # un lot lent : le client (délai d'inactivité 30 s) ne coupe jamais.
    async for _ in _avec_battement(generation.completer(
        ensemble, contexte=contexte, fournis=fournis, appeler=appel_lot(llm, settings),
        max_requetes=settings.propositions_max_requetes,
        attente_max=settings.propositions_attente_max,
        tons_par_lot=settings.propositions_tons_par_lot,
        plafond_sortie=settings.propositions_lot_max_tokens,
    )):
        yield None


# --- Route --------------------------------------------------------------------------

def get_comprehension(
    supabase: SupabaseAdmin = Depends(get_supabase),
    redis: Redis = Depends(get_redis),
    settings: Settings = Depends(get_settings),
) -> MoteurComprehension:
    return MoteurComprehension(supabase, redis, settings)


CONSENTEMENT_REQUIS = {
    "code": "consentement_requis",
    "message": (
        "Ce chat contient des conversations WhatsApp jointes : leur analyse "
        "nécessite l'accord de l'utilisateur pour envoyer les extraits utiles "
        "au fournisseur IA."
    ),
}


@router.post("/stream")
async def chat_stream(
    body: ChatRequest,
    # Avant le quota : un fournisseur refusé ou mal configuré ne consomme rien.
    llm: FournisseurLLM = Depends(get_fournisseur),
    reservation: QuotaReservation = Depends(enforce_quota),
    quota_service: QuotaService = Depends(get_quota_service),
    supabase: SupabaseAdmin = Depends(get_supabase),
    redis: Redis = Depends(get_redis),
    settings: Settings = Depends(get_settings),
    comprehension: MoteurComprehension = Depends(get_comprehension),
    odo: ServiceODO = Depends(get_odo),
) -> StreamingResponse:
    user_id = reservation.user.id
    now = datetime.now(timezone.utc)
    debut = time.perf_counter()
    question = body.message
    consigne = None
    preparation: Preparation | None = None
    aide_probable = False
    precedentes = None   # dernières propositions de réponse du chat
    cibles = []          # pièces jointes visées (messages chargés)
    envoyees = None      # réponses déclarées envoyées à ces contacts
    reduire = None   # préparation plus petite, si le fournisseur refuse (413)

    # Préparation : tout échec ici rend la requête au quota.
    try:
        if body.reply_to is not None and body.conversation_id is None:
            raise HTTPException(422, detail="reply_to exige conversation_id")
        if body.conversation_id is not None:
            conversation = await supabase.get_conversation(str(body.conversation_id), user_id)
            if conversation is None:
                raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Conversation introuvable")
            new_conversation = False
            history = await load_context(redis, supabase, conversation["id"], settings)
            contextes = await comprehension.contextes(user_id, conversation["id"])
        else:
            conversation = await supabase.create_conversation(user_id, conversation_title(body.message))
            new_conversation = True
            history = []
            contextes = []

        if body.reply_to is not None:
            consigne = await supabase.get_user_message(str(body.reply_to), user_id)
            if consigne is None or consigne["conversation_id"] != conversation["id"]:
                raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Consigne introuvable")
            question = consigne["content"]
            # La consigne est déjà le dernier message de l'historique : elle
            # devient la question (jamais deux fois).
            if history and history[-1]["role"] == "user" and history[-1]["content"] == question:
                history = history[:-1]

        systeme = build_system_prompt(body.ton, conversation.get("persona"), now)
        if contextes:
            # Aucun appel au fournisseur sans réponse explicite de
            # l'utilisateur sur l'envoi des messages WhatsApp.
            if body.whatsapp_analysis is None:
                raise HTTPException(status.HTTP_409_CONFLICT, detail=CONSENTEMENT_REQUIS)
            if body.whatsapp_analysis == "declined":
                preparation = comprehension.sans_consentement(
                    systeme=systeme, historique=history, question=question
                )
            else:
                cibles = choisir(contextes, question, consigne["id"] if consigne else None)
                for c in cibles:
                    await comprehension.charger(c, user_id)
                # Message visé (« sa dernière réponse »…) : choisi ici, dans
                # les messages enregistrés, avant tout appel à l'IA.
                visee = ciblage.cibler(question, cibles, [m["content"] for m in history if m["role"] == "user"])
                # « Pourquoi tu dis ça ? » : les messages qui fondaient les
                # deux dernières réponses sont fournis de nouveau.
                recentes = await supabase.get_assistant_attachments(conversation["id"], user_id, limit=3)
                cites = restauration.cites(recentes[:2])
                for ctx_id, rangs in ciblage.voisins(visee).items():
                    cites.setdefault(ctx_id, set()).update(rangs)
                if visee is not None:
                    # Genre et rang seulement : jamais de contenu.
                    logger.info("Ciblage : %s", f"{visee.cible.genre}, rang {visee.cible.message.ordre}, "
                                f"{visee.cible.message.origine}" if visee.cible else
                                f"clarification ({len(visee.ambigus)} candidat(s))")
                # Dernières propositions de réponse (phase 3), pour en discuter.
                if body.propositions_message_id is not None:
                    ligne = await supabase.get_assistant_message(
                        str(body.propositions_message_id), conversation["id"], user_id
                    )
                    if ligne is not None:
                        precedentes = aide.lues(ligne.get("attachments"), str(ligne["id"]))
                        if precedentes is not None and not precedentes.get("tons"):
                            precedentes = None     # ensemble incomplet : rien à discuter
                    else:
                        logger.warning("Propositions référencées hors de ce chat ou de ce compte : ignorées")
                if precedentes is None:
                    precedentes = next(
                        (p for p in (aide.lues(l.get("attachments"), str(l["id"])) for l in recentes)
                         if p and p.get("tons")),
                        None,
                    )
                # Réponses déclarées envoyées à ce(s) contact(s) (phase 4).
                envoyees = await memoire.pour_contacts(supabase, user_id, cibles)
                if precedentes:
                    for a in aide.appuis(precedentes):
                        try:
                            cites.setdefault(str(a["context_id"]), set()).add(int(a["message_order"]))
                        except (KeyError, TypeError, ValueError):
                            continue
                # Demande probable d'aide à répondre (simple indice : c'est le
                # modèle qui décide) : de la place pour les lots de
                # propositions qui suivent, dans la même limite par minute.
                aide_probable = reperes.analyser(question, [], now.date()).aide_reponse
                budget_entree = llm.budget_comprehension or settings.comprehension_budget_tokens
                if aide_probable:
                    budget_entree -= settings.comprehension_extra_output_tokens

                def preparer(budget: int) -> Preparation:
                    return comprehension.preparer(
                        systeme=systeme,
                        contextes=contextes,
                        cibles=cibles,
                        historique=history,
                        question=question,
                        aujourd_hui=now.date(),
                        budget=budget,
                        cites=cites,
                        propositions_faites=precedentes,
                        ton_affiche=body.ton_propose,
                        longueur_affichee=body.longueur_proposee,
                        envoyees=envoyees,
                        ciblage=visee,
                    )

                preparation = preparer(budget_entree)

                def reduire() -> Preparation:
                    return preparer(int(budget_entree * 0.6))

                # Volumes seulement : jamais de contenu.
                logger.info(
                    "Compréhension : %d pièce(s) jointe(s), %d message(s) fournis, complète=%s, ~%d tokens, "
                    "préparation %d ms",
                    len(preparation.contextes), len(preparation.references),
                    preparation.complete, preparation.tokens_estimes,
                    (time.perf_counter() - debut) * 1000,
                )
        elif consigne is not None:
            # Pièce jointe supprimée depuis : rien à analyser, rien à inventer.
            systeme += "\n\n" + NOTE_PIECE_SUPPRIMEE
    except HTTPException:
        await quota_service.release(reservation)
        raise
    except httpx.HTTPError:
        await quota_service.release(reservation)
        logger.error("Supabase indisponible pendant la préparation du chat", exc_info=True)
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, detail="Base de données indisponible")

    conversation_id = conversation["id"]
    user_row = None if consigne is not None else {
        "id": str(uuid4()),
        "conversation_id": conversation_id,
        "user_id": user_id,
        "role": "user",
        "content": body.message,
        "created_at": now.isoformat(),
    }
    assistant_id = str(uuid4())
    if preparation is not None:
        prompt = preparation.messages
        # La réponse principale n'écrit plus les propositions (lots) : sortie normale.
        max_sortie = plafond(llm, settings.comprehension_max_output_tokens, settings)
    else:
        prompt = [
            {"role": "system", "content": systeme},
            *history,
            {"role": "user", "content": question},
        ]
        max_sortie = plafond(llm, settings.chat_max_output_tokens, settings)

    # Contrôle avant l'appel facturable : une demande dont l'entrée estimée
    # dépasse déjà les tokens restants (jour ou session) n'est pas envoyée.
    depassement = quota_service.budget_depasse(
        reservation, estimate_tokens("".join(m["content"] for m in prompt)))
    if depassement:
        await quota_service.release(reservation)
        logger.info("Demande refusée avant l'appel : %s", depassement)
        raise quota_exceeded(depassement, reservation.status)

    demande_id = consigne["id"] if consigne is not None else user_row["id"]

    # ODO : chat ordinaire seulement (WhatsApp et consignes : chemin actuel).
    # Identité et offre du serveur ; budget du jour revérifié avant chaque tour.
    execution = None
    if preparation is None and consigne is None:
        execution = odo.execution(
            llm,
            odo.contexte(user_id=user_id, demande_id=demande_id, plan=reservation.status.plan,
                         conversation_id=conversation_id),
            verifier_budget=lambda tokens: quota_service.budget_depasse(reservation, tokens),
        )
    source = execution.flux if execution is not None else llm.flux

    async def event_stream():
        nonlocal prompt, preparation
        parts: list[str] = []
        fin: Fin | None = None     # fin normale du fournisseur (usage, modèle, raison)
        lots = [0, 0]      # tokens (entrée, sortie) des lots de propositions
        # Repères [[n]] retirés du texte diffusé (WhatsApp seulement : un
        # chat ordinaire n'a aucun message numéroté).
        # Chaque phrase est contrôlée (auteurs enregistrés) avant d'être
        # diffusée : une attribution fausse n'est jamais affichée.
        correcteur = None
        filtre = None
        blocs = None     # bloc <propositions> retiré du texte (phase 3)
        if preparation is not None and preparation.fournis:
            # Propositions déjà faites : jamais prises pour des messages
            # WhatsApp ; une proposition mal recopiée est rétablie.
            vise = (aide.visee(precedentes, body.ton_propose, question, body.longueur_proposee)
                    if precedentes else None)
            correcteur = CorrecteurAttributions(
                preparation.fournis,
                propositions=[x["texte"] for t in (precedentes or {}).get("tons", []) for x in t["propositions"]],
                visee=vise[2]["texte"] if vise else None,
            )
            filtre = FiltreReperes(correcteur)
            blocs = aide.FiltrePropositions()

        def visible(fragment: str) -> str:
            if blocs is not None:
                fragment = blocs.ajouter(fragment)
            return filtre.ajouter(fragment) if filtre else fragment
        stockees: list[dict] = []
        try:
            yield sse("meta", {
                "conversation_id": conversation_id,
                "message_id": assistant_id,
                "quota": reservation.status.to_dict(),
            })

            # Les attentes (limite de débit, surcharge) sont gérées ici, flux
            # ouvert ; une nouvelle tentative n'a lieu que si RIEN n'a encore
            # été diffusé (jamais de texte en double).
            attendu = 0.0
            reduit = False
            appel = time.perf_counter()
            premier = None
            while True:
                try:
                    async for ev in _avec_battement(source(prompt, max_sortie=max_sortie)):
                        if ev is None:
                            yield b": le modele reflechit\n\n"
                        elif isinstance(ev, EtatOutil):
                            yield sse("outil", {"nom": ev.nom, "etat": ev.etat, "code": ev.code})
                        elif isinstance(ev, DemandeConfirmation):
                            confirmation = {"id": ev.id, "outil": ev.outil, "resume": ev.resume,
                                            "expire_at": ev.expire_a}
                            stockees.append({"type": "odo_confirmation", **confirmation})
                            yield sse("confirmation", confirmation)
                        elif isinstance(ev, Texte):
                            if premier is None:
                                premier = time.perf_counter()
                            parts.append(ev.texte)
                            texte_visible = visible(ev.texte)
                            if texte_visible:
                                yield sse("delta", {"text": texte_visible})
                        elif isinstance(ev, Fin):
                            fin = ev
                    break
                except LimiteDebit as exc:
                    if exc.apres_texte or exc.attente is None or attendu + exc.attente > settings.llm_rate_limit_max_wait:
                        raise
                    attendu += exc.attente
                    horloge = asyncio.get_running_loop()
                    echeance = horloge.time() + exc.attente
                    while (reste := echeance - horloge.time()) > 0:
                        # Commentaire SSE : la connexion reste vivante.
                        yield b": attente du fournisseur IA\n\n"
                        await asyncio.sleep(min(5.0, reste))
                except RequeteTropGrande as exc:
                    if exc.apres_texte or reduire is None or reduit:
                        raise
                    reduit = True
                    preparation = reduire()
                    prompt = preparation.messages
                    if correcteur is not None:
                        correcteur.fournis = preparation.fournis

            if fin is None:
                # Flux terminé sans fin annoncée : réponse incomplète.
                raise ErreurFournisseur("llm_unavailable", fournisseur=llm.nom, apres_texte=bool(parts))
            if fin.raison is not RaisonArret.FIN:
                # Refus du modèle ou plafond de sortie atteint : jamais
                # présenté comme une réponse terminée (pas de `done`).
                raise ErreurFournisseur(
                    "llm_refus" if fin.raison is RaisonArret.REFUS else "llm_incomplet",
                    fournisseur=llm.nom, apres_texte=bool(parts),
                    message=(MESSAGES_LLM["llm_refus"] if fin.raison is RaisonArret.REFUS
                             else "La réponse a été coupée avant la fin. Renvoie ta question pour la réponse complète."),
                )
            ensemble = None
            if filtre is not None:
                reste = filtre.ajouter(blocs.terminer()) + filtre.terminer()
                if blocs.bloc is not None:
                    # Mode et tons annoncés ; les messages viennent des lots.
                    ensemble = generation.annoncer(
                        blocs.bloc, preparation.fournis,
                        preparation.contextes[0] if preparation.contextes else None, demande_id,
                    )
                    if ensemble is not None and not (filtre.visible + reste).strip():
                        # Jamais de réponse vide : une introduction minimale.
                        reste += filtre.ajouter(
                            "Voici quelques idées de relance." if ensemble.mode == "relance"
                            else "Voici quelques idées de réponse."
                        ) + filtre.terminer()
                if reste:
                    yield sse("delta", {"text": reste})
                # Contrôle de chaque repère avec les messages réellement
                # fournis ; seules les références vérifiées partent.
                propres = [x["texte"] for t in (precedentes or {}).get("tons", []) for x in t["propositions"]]
                verification = verifier(filtre.visible, filtre.reperes, preparation.fournis, propres)
                verification.corrigees = correcteur.corrigees
                verification.ecartees = correcteur.ecartees
                stockees = [entree_stockee(r) for r in verification.references]
                note = verification.note
                if note:
                    stockees.append({"type": restauration.TYPE_NOTE, "text": note})
                if verification.references or note:
                    yield sse("references", {
                        "message_id": assistant_id,
                        "references": verification.references,
                        "note": note,
                    })
                if ensemble is not None:
                    # Toutes les combinaisons sont préparées AVANT d'être
                    # disponibles ; sinon « incomplet » (lots valides gardés).
                    ctx = next((c for c in cibles if c.id == ensemble.context_id), None)
                    if ctx is None:
                        ensemble.raison = "erreur"
                    elif not ensemble.complet:
                        # Le texte est fini, les propositions se préparent :
                        # l'appli garde un indicateur vivant (« … »).
                        yield sse("preparation", {"message_id": assistant_id, "etape": "propositions"})
                        debut_lots = time.perf_counter()
                        memoire_bloc = (aide.bloc_memoire(envoyees[ctx.id], ctx.contact)
                                        if envoyees and envoyees.get(ctx.id) else None)
                        async for _ in completer_ensemble(
                            ensemble, ctx, question=question, analyse=filtre.visible,
                            aujourd_hui=now.date(), memoire_bloc=memoire_bloc,
                            llm=llm, settings=settings,
                        ):
                            yield b": preparation des propositions\n\n"
                    if ensemble.requetes:
                        logger.info("Durée : lots de propositions %d ms (%d requête(s))",
                                    (time.perf_counter() - debut_lots) * 1000, ensemble.requetes)
                    lots[0], lots[1] = ensemble.tokens_entree, ensemble.tokens_sortie
                    entree = ensemble.stockage()
                    stockees.append(entree)
                    yield sse("propositions", {"message_id": assistant_id, **aide.lues([entree], assistant_id)})
                    logger.info(
                        "Propositions : mode=%s, %d ton(s), statut=%s, %d lot(s), %d manquante(s)",
                        ensemble.mode, len(ensemble.tons), entree["statut"], ensemble.requetes,
                        ensemble.nombre_manquant(),
                    )
                logger.info(
                    "Références : %d vérifiée(s), %d refusée(s), %d attribution(s) contredite(s), "
                    "%d corrigée(s), %d écartée(s)",
                    len(verification.references), verification.refusees,
                    verification.attributions_contredites, correcteur.corrigees, correcteur.ecartees,
                )

            logger.info("Durée : premier fragment %s ms, réponse principale %d ms",
                        "-" if premier is None else int((premier - appel) * 1000),
                        (time.perf_counter() - appel) * 1000)
            text = filtre.visible if filtre else "".join(parts)
            prompt_tokens, completion_tokens = _token_counts(fin.usage if fin else None, prompt, text)
            prompt_tokens += lots[0]
            completion_tokens += lots[1]
            final_quota = replace(
                reservation.status,
                tokens_used=reservation.status.tokens_used + prompt_tokens + completion_tokens,
            )
            yield sse("done", {
                "message_id": assistant_id,
                "usage": {
                    "prompt_tokens": prompt_tokens,
                    "completion_tokens": completion_tokens,
                    "total_tokens": prompt_tokens + completion_tokens,
                },
                "quota": final_quota.to_dict(),
            })
        except Exception as exc:
            # Type et code d'erreur seulement : jamais le contenu du prompt.
            logger.error(
                "Échec de génération (conversation=%s, fournisseur=%s) : %s %s", conversation_id, llm.nom,
                type(exc).__name__, getattr(exc, "code", ""),
            )
            yield sse("error", describe_llm_error(exc))
        finally:
            # Exécuté aussi si le client se déconnecte en plein flux :
            # la réponse partielle est enregistrée et facturée.
            if filtre is not None:
                filtre.ajouter(blocs.terminer())
                filtre.terminer()
                text = filtre.visible
            else:
                text = "".join(parts)
            if fin is None and execution is not None:
                # Interrompu pendant ODO : tours terminés + tour en cours (estimé).
                prompt_tokens, completion_tokens = execution.usage_consomme()
            else:
                prompt_tokens, completion_tokens = _token_counts(fin.usage if fin else None, prompt, text)
            prompt_tokens += lots[0]
            completion_tokens += lots[1]
            _spawn(_finalize_safely(
                quota_service=quota_service,
                supabase=supabase,
                redis=redis,
                settings=settings,
                reservation=reservation,
                conversation_id=conversation_id,
                new_conversation=new_conversation,
                user_row=user_row,
                assistant_id=assistant_id,
                text=text,
                prompt_tokens=prompt_tokens,
                completion_tokens=completion_tokens,
                model=fin.modele if fin is not None else llm.modele,
                provider=llm.nom,
                attachments=stockees,
            ))

    return StreamingResponse(
        event_stream(),
        media_type="text/event-stream",
        headers={
            **reservation.status.headers(),
            ENTETE_FOURNISSEUR: llm.nom,
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",  # désactive le buffering nginx / proxies
        },
    )


def _token_counts(usage: Usage | None, prompt: list[dict], text: str) -> tuple[int, int]:
    """(entrée, sortie) : usage du fournisseur (cache compris en entrée,
    réflexion interne comprise en sortie), sinon estimation (flux coupé)."""
    if usage is not None and not (usage.estime and usage.total == 0):
        return usage.entree_totale, usage.sortie
    prompt_chars = "".join(m["content"] for m in prompt)
    return estimate_tokens(prompt_chars), (estimate_tokens(text) if text else 0)
