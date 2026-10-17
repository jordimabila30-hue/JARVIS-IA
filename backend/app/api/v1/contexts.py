"""Contextes WhatsApp joints aux conversations JARVIS (Authorization : Bearer
<jwt Supabase> sur toutes les routes).

POST   /api/v1/conversations/contexts          consigne + pièce jointe, en une
                                                transaction (chat existant si
                                                `conversation_id`, sinon créé)
GET    /api/v1/conversations/{id}/contexts      pièces jointes d'un chat
GET    /api/v1/conversations/{id}/references    {"items": [...]} : références des
                                                réponses de JARVIS (relues
                                                dans Supabase)
GET    /api/v1/contexts/{id}                    une pièce jointe (métadonnées)
GET    /api/v1/contexts/{id}/messages           ses messages, par pages
                                                (?after=<rang>&limit=<n>)
DELETE /api/v1/contexts/{id}                    supprime la pièce jointe et
                                                ses messages (pas le chat)

Logique dans app/contextes.py. Aucun appel à l'IA ni au quota.
"""

import logging
from datetime import datetime, timezone
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, Request, Response, status
from pydantic import ValidationError
from redis.asyncio import Redis
from redis.exceptions import RedisError

import httpx

from ...auth import AuthUser, get_current_user
from ...ajouts_manuels import AjoutsManuels, AuteurInvalide, Correspondances, MessageIntrouvable, MessageOriginal
from ...comprehension import generation, memoire, propositions as aide, restauration
from ...comprehension.moteur import MoteurComprehension
from ...llm import FournisseurLLM
from ...quota import QuotaReservation, QuotaService, enforce_quota, get_quota_service
from ...config import Settings, get_settings
from ...contextes import (
    _contexte,
    BaseIndisponible,
    ContexteIntrouvable,
    ContextesService,
    ConversationIntrouvable,
    DonneesInvalides,
    ErreurContexte,
    IdentifiantDejaUtilise,
    RequeteTropVolumineuse,
)
from ...contextes_modeles import (
    AddMessagesRequest,
    ContextMessageOut,
    ContextMessagesPage,
    ContextOut,
    SaveContextRequest,
    SaveContextResponse,
    UpdateManualMessage,
)
from ...redis_client import get_redis
from ...supabase_client import SupabaseAdmin, get_supabase
from .chat import completer_ensemble, context_key, get_comprehension, get_fournisseur

logger = logging.getLogger(__name__)

conversations_router = APIRouter(prefix="/conversations", tags=["contextes WhatsApp"])
contexts_router = APIRouter(prefix="/contexts", tags=["contextes WhatsApp"])

# Réponses d'erreur : jamais de détail de la base.
_HTTP = {
    ConversationIntrouvable: (status.HTTP_404_NOT_FOUND, "Conversation introuvable"),
    ContexteIntrouvable: (status.HTTP_404_NOT_FOUND, "Pièce jointe introuvable"),
    IdentifiantDejaUtilise: (status.HTTP_409_CONFLICT, "Identifiant déjà utilisé"),
    DonneesInvalides: (422, "Données invalides"),
    RequeteTropVolumineuse: (413, "Pièce jointe trop volumineuse"),
    BaseIndisponible: (status.HTTP_503_SERVICE_UNAVAILABLE, "Base de données indisponible"),
}


def _http(exc: ErreurContexte) -> HTTPException:
    code, detail = _HTTP.get(type(exc), (status.HTTP_503_SERVICE_UNAVAILABLE, "Erreur interne"))
    return HTTPException(code, detail=detail)


def get_contextes(
    supabase: SupabaseAdmin = Depends(get_supabase),
    settings: Settings = Depends(get_settings),
) -> ContextesService:
    return ContextesService(supabase, settings)


@conversations_router.post(
    "/contexts",
    status_code=status.HTTP_201_CREATED,
    response_model=SaveContextResponse,
    openapi_extra={
        "requestBody": {
            "required": True,
            "content": {"application/json": {"schema": SaveContextRequest.model_json_schema()}},
        }
    },
)
async def save_context(
    request: Request,
    response: Response,
    user: AuthUser = Depends(get_current_user),
    service: ContextesService = Depends(get_contextes),
    settings: Settings = Depends(get_settings),
    redis: Redis = Depends(get_redis),
) -> SaveContextResponse:
    """Enregistre une consigne et sa pièce jointe WhatsApp (201), ou renvoie
    l'enregistrement existant pour un réessai du même `context_id` (200)."""
    # Taille vérifiée AVANT de lire le corps (des milliers de messages).
    taille = request.headers.get("content-length")
    if taille is not None and taille.isdigit() and int(taille) > settings.whatsapp_context_max_bytes:
        raise _http(RequeteTropVolumineuse())
    corps = await request.body()
    if len(corps) > settings.whatsapp_context_max_bytes:
        raise _http(RequeteTropVolumineuse())
    try:
        demande = SaveContextRequest.model_validate_json(corps)
    except ValidationError as exc:
        # Champs et raisons seulement : jamais le contenu des messages.
        raise HTTPException(
            422,
            detail=[{"loc": e["loc"], "msg": e["msg"]} for e in exc.errors()],
        ) from None

    try:
        resultat = await service.enregistrer(user.id, demande)
    except ErreurContexte as exc:
        raise _http(exc) from None

    if resultat.already_saved:
        response.status_code = status.HTTP_200_OK
    else:
        # La consigne entre dans l'historique : le contexte court de l'IA
        # sera relu depuis Supabase.
        try:
            await redis.delete(context_key(str(resultat.conversation_id)))
        except RedisError:
            logger.warning("Contexte Redis non invalidé", exc_info=True)
    return resultat


@conversations_router.get("/{conversation_id}/contexts", response_model=list[ContextOut])
async def list_contexts(
    conversation_id: UUID,
    user: AuthUser = Depends(get_current_user),
    service: ContextesService = Depends(get_contextes),
) -> list[ContextOut]:
    """Pièces jointes d'un chat du compte, de la plus ancienne à la plus
    récente, avec leur nombre réel de messages (sans les messages)."""
    try:
        return await service.lister(user.id, str(conversation_id))
    except ErreurContexte as exc:
        raise _http(exc) from None


@conversations_router.get("/{conversation_id}/references")
async def list_references(
    conversation_id: UUID,
    user: AuthUser = Depends(get_current_user),
    supabase: SupabaseAdmin = Depends(get_supabase),
) -> dict:
    """Références des réponses de JARVIS de ce chat : identifiants relus
    dans `messages.attachments`, messages relus dans `context_messages`,
    tout filtré par le compte du JWT. Un message supprimé n'apparaît plus."""
    try:
        if await supabase.get_conversation(str(conversation_id), user.id) is None:
            raise _http(ConversationIntrouvable())
        return {"items": await restauration.references_conversation(supabase, user.id, str(conversation_id))}
    except httpx.HTTPError:
        logger.error("Supabase indisponible (références)", exc_info=True)
        raise _http(BaseIndisponible()) from None


_ENVOYEE = "/{conversation_id}/messages/{message_id}/propositions/{proposition_id}/envoyee"


async def _declaration(action, conversation_id: UUID, message_id: UUID, proposition_id: UUID,
                       user: AuthUser, supabase: SupabaseAdmin) -> dict:
    try:
        return await action(supabase, user.id, str(conversation_id), str(message_id), str(proposition_id))
    except memoire.DejaChoisi as exc:
        # Une seule réponse envoyée par ensemble de propositions.
        raise HTTPException(status.HTTP_409_CONFLICT, detail={
            "code": "deja_choisi", "proposition_id": exc.proposition_id,
            "message": "Une autre proposition de cet ensemble est déjà choisie."}) from None
    except memoire.PropositionIntrouvable:
        # Autre compte, autre chat, ou identifiant inconnu : même réponse.
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Proposition introuvable") from None
    except httpx.HTTPError:
        logger.error("Supabase indisponible (réponse déclarée envoyée)", exc_info=True)
        raise _http(BaseIndisponible()) from None


@conversations_router.put(_ENVOYEE)
async def declarer_envoyee(
    conversation_id: UUID, message_id: UUID, proposition_id: UUID,
    user: AuthUser = Depends(get_current_user),
    supabase: SupabaseAdmin = Depends(get_supabase),
) -> dict:
    """Phase 4 : l'utilisateur DÉCLARE avoir envoyé cette proposition
    (appui long). Idempotent. Rien n'est envoyé à WhatsApp."""
    return await _declaration(memoire.declarer, conversation_id, message_id, proposition_id, user, supabase)


@conversations_router.delete(_ENVOYEE)
async def annuler_envoyee(
    conversation_id: UUID, message_id: UUID, proposition_id: UUID,
    user: AuthUser = Depends(get_current_user),
    supabase: SupabaseAdmin = Depends(get_supabase),
) -> dict:
    """Annule la déclaration (gardée avec sa date d'annulation)."""
    return await _declaration(memoire.annuler, conversation_id, message_id, proposition_id, user, supabase)


# --- Reprise d'une génération de propositions incomplète ----------------------

def _verrou(message_id: str) -> str:
    return f"propgen:{message_id}"


@conversations_router.post("/{conversation_id}/messages/{message_id}/propositions/completer")
async def completer_propositions(
    conversation_id: UUID, message_id: UUID,
    # Avant le quota : un fournisseur refusé ou mal configuré ne consomme rien.
    llm: FournisseurLLM = Depends(get_fournisseur),
    reservation: QuotaReservation = Depends(enforce_quota),
    quota_service: QuotaService = Depends(get_quota_service),
    supabase: SupabaseAdmin = Depends(get_supabase),
    redis: Redis = Depends(get_redis),
    settings: Settings = Depends(get_settings),
    comprehension: MoteurComprehension = Depends(get_comprehension),
) -> dict:
    """« Reprendre » : complète SEULEMENT les combinaisons manquantes d'un
    ensemble incomplet, dans le même ensemble (même réponse, mêmes
    identifiants pour ce qui était déjà valide). Ensemble déjà complet :
    renvoyé tel quel, sans appel à l'IA. Une seule reprise à la fois."""
    user_id = reservation.user.id
    tokens = 0
    verrou = False
    try:
        ligne = await supabase.get_assistant_message(str(message_id), str(conversation_id), user_id)
        entree = next((a for a in (ligne or {}).get("attachments") or []
                       if isinstance(a, dict) and a.get("type") == aide.TYPE), None)
        if entree is None:
            raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Propositions introuvables")
        if entree.get("statut") != generation.STATUT_INCOMPLET:
            return {"propositions": aide.lues(ligne["attachments"], str(message_id))}
        try:
            verrou = bool(await redis.set(_verrou(str(message_id)), "1", nx=True, ex=180))
        except RedisError:
            verrou = True        # Redis absent : on continue sans protection
        if not verrou:
            raise HTTPException(status.HTTP_409_CONFLICT, detail={
                "code": "generation_en_cours",
                "message": "Ces propositions sont déjà en cours de préparation."})
        ensemble = generation.Ensemble.depuis_stockage(entree)
        ctx = next((c for c in await comprehension.contextes(user_id, str(conversation_id))
                    if c.id == ensemble.context_id), None)
        if ctx is None:
            raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Pièce jointe introuvable")
        await comprehension.charger(ctx, user_id)
        demande = (await supabase.get_user_message(ensemble.demande_id, user_id)
                   if ensemble.demande_id else None)
        envoyees = await memoire.pour_contacts(supabase, user_id, [ctx])
        memoire_bloc = aide.bloc_memoire(envoyees[ctx.id], ctx.contact) if envoyees.get(ctx.id) else None
        ensemble.raison = None
        async for _ in completer_ensemble(
            ensemble, ctx, question=(demande or {}).get("content") or "",
            analyse=ligne.get("content") or "", aujourd_hui=datetime.now(timezone.utc).date(),
            memoire_bloc=memoire_bloc, llm=llm, settings=settings,
        ):
            pass
        tokens = ensemble.tokens_entree + ensemble.tokens_sortie
        # Relu juste avant l'écriture : seule l'entrée des propositions change.
        actuelle = await supabase.get_assistant_message(str(message_id), str(conversation_id), user_id)
        nouvelle = ensemble.stockage()
        pieces = [nouvelle if isinstance(a, dict) and a.get("type") == aide.TYPE else a
                  for a in (actuelle or ligne).get("attachments") or []]
        await supabase.update_message_attachments(str(message_id), user_id, pieces)
        logger.info("Reprise des propositions : statut=%s, %d lot(s), %d manquante(s)",
                    nouvelle["statut"], ensemble.requetes, ensemble.nombre_manquant())
        return {"propositions": aide.lues(pieces, str(message_id))}
    except httpx.HTTPError:
        logger.error("Supabase indisponible (reprise des propositions)", exc_info=True)
        raise _http(BaseIndisponible()) from None
    finally:
        if tokens:
            await quota_service.record_usage(reservation, tokens)
        else:
            await quota_service.release(reservation)
        if verrou:
            try:
                await redis.delete(_verrou(str(message_id)))
            except RedisError:
                pass


# --- Phase 5 : actualisation manuelle (copier-coller) -------------------------

def get_ajouts(
    supabase: SupabaseAdmin = Depends(get_supabase),
    redis: Redis = Depends(get_redis),
) -> AjoutsManuels:
    return AjoutsManuels(supabase, redis)


def _http_ajout(exc: Exception) -> HTTPException:
    if isinstance(exc, Correspondances):
        return HTTPException(status.HTTP_409_CONFLICT, detail={
            "code": "correspondances",
            "message": "Ces messages ressemblent à des messages déjà connus. Confirmez avant de les ajouter.",
            "items": exc.items,
        })
    if isinstance(exc, AuteurInvalide):
        return HTTPException(422, detail={"code": "auteur_invalide", "message": exc.detail})
    if isinstance(exc, MessageOriginal):
        return HTTPException(status.HTTP_409_CONFLICT, detail={
            "code": "message_original",
            "message": "Un message importé depuis WhatsApp ne peut pas être modifié."})
    if isinstance(exc, MessageIntrouvable):
        return HTTPException(status.HTTP_404_NOT_FOUND, detail="Message introuvable")
    return _http(exc)


@contexts_router.get("")
async def list_all_contexts(
    user: AuthUser = Depends(get_current_user),
    supabase: SupabaseAdmin = Depends(get_supabase),
) -> dict:
    """Pièces jointes WhatsApp du compte (volet « Ajouter une réponse
    reçue » ouvert hors d'un chat WhatsApp)."""
    try:
        lignes = await supabase.list_user_contexts(user.id)
    except httpx.HTTPError:
        logger.error("Supabase indisponible (liste des contextes)", exc_info=True)
        raise _http(BaseIndisponible()) from None
    return {"items": [_contexte(l) for l in lignes]}


@contexts_router.post("/{context_id}/messages", status_code=status.HTTP_201_CREATED)
async def add_context_messages(
    context_id: UUID,
    body: AddMessagesRequest,
    user: AuthUser = Depends(get_current_user),
    ajouts: AjoutsManuels = Depends(get_ajouts),
) -> dict:
    """Ajoute à la suite du contexte des messages collés par l'utilisateur
    (reçus / envoyés). Atomique, idempotent, aucun appel à l'IA."""
    try:
        return {"messages": await ajouts.ajouter(user.id, str(context_id), body)}
    except (ErreurContexte, Correspondances) as exc:
        raise _http_ajout(exc) from None


@contexts_router.patch("/{context_id}/messages/{message_id}")
async def update_context_message(
    context_id: UUID,
    message_id: UUID,
    body: UpdateManualMessage,
    user: AuthUser = Depends(get_current_user),
    ajouts: AjoutsManuels = Depends(get_ajouts),
) -> ContextMessageOut:
    """Corrige un message AJOUTÉ (texte, auteur, date) ; jamais un import."""
    try:
        return await ajouts.modifier(user.id, str(context_id), str(message_id), body)
    except ErreurContexte as exc:
        raise _http_ajout(exc) from None


@contexts_router.delete("/{context_id}/messages/{message_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_context_message(
    context_id: UUID,
    message_id: UUID,
    user: AuthUser = Depends(get_current_user),
    ajouts: AjoutsManuels = Depends(get_ajouts),
) -> Response:
    """Supprime un message AJOUTÉ par erreur ; jamais un message importé."""
    try:
        await ajouts.supprimer(user.id, str(context_id), str(message_id))
    except ErreurContexte as exc:
        raise _http_ajout(exc) from None
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@contexts_router.get("/{context_id}", response_model=ContextOut)
async def get_context(
    context_id: UUID,
    user: AuthUser = Depends(get_current_user),
    service: ContextesService = Depends(get_contextes),
) -> ContextOut:
    try:
        return await service.obtenir(user.id, str(context_id))
    except ErreurContexte as exc:
        raise _http(exc) from None


@contexts_router.get("/{context_id}/messages", response_model=ContextMessagesPage)
async def get_context_messages(
    context_id: UUID,
    after: int = Query(-1, ge=-1, description="Rang du dernier message reçu (-1 : début)"),
    limit: int = Query(200, ge=1, description="Messages par page (borné par la configuration)"),
    manual: bool = Query(False, description="Seulement les messages ajoutés à la main (phase 5)"),
    user: AuthUser = Depends(get_current_user),
    service: ContextesService = Depends(get_contextes),
) -> ContextMessagesPage:
    try:
        return await service.messages(user.id, str(context_id), after=after, limit=limit, manuels=manual)
    except ErreurContexte as exc:
        raise _http(exc) from None


@contexts_router.delete("/{context_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_context(
    context_id: UUID,
    user: AuthUser = Depends(get_current_user),
    service: ContextesService = Depends(get_contextes),
) -> Response:
    """Supprime la pièce jointe et ses messages ; le chat, la consigne et
    les autres pièces jointes restent."""
    try:
        await service.supprimer(user.id, str(context_id))
    except ErreurContexte as exc:
        raise _http(exc) from None
    return Response(status_code=status.HTTP_204_NO_CONTENT)
