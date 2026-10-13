"""Historique des échanges traités localement par l'application JARVIS.

POST /api/v1/conversations/local-exchanges   (Authorization: Bearer <jwt Supabase>)
  corps : {
    "question_id": "<uuid>",          identifiant du message utilisateur (clé d'idempotence)
    "answer_id": "<uuid>",            identifiant de la réponse locale
    "conversation_id": "<uuid>"|null, conversation existante du compte, ou null (création)
    "question": "...", "answer": "...",
    "question_at": "<iso>"|null, "answer_at": "<iso>"|null
  }

L'application exécute elle-même certaines commandes (heure, calcul…) : rien
n'est généré ici. Cette route ne fait que les enregistrer dans la conversation
du compte, pour les retrouver sur ses autres appareils :
  - le compte vient du JWT vérifié, jamais du corps de la requête ;
  - une conversation fournie doit appartenir à ce compte (sinon 404) ;
  - aucun appel au fournisseur IA, aucun quota de génération consommé ;
  - la réponse est marquée `model = "jarvis-local"` (jamais confondue avec une
    réponse du modèle) ; le contenu est stocké tel quel, comme message
    `user` / `assistant` de la conversation, jamais comme instruction système ;
  - réessai (réseau coupé après l'enregistrement) : `question_id` déjà connu
    pour ce compte -> rien n'est réinséré, la conversation existante est
    renvoyée (200) ;
  - l'heure fournie par l'appareil (corrigée de son décalage) garde l'ordre
    des messages ; elle est bornée (jamais dans le futur, au plus 30 jours
    en arrière).
"""

import logging
from datetime import datetime, timedelta, timezone
from uuid import UUID

import httpx
from fastapi import APIRouter, Depends, HTTPException, Response, status
from pydantic import BaseModel, Field
from redis.asyncio import Redis
from redis.exceptions import RedisError

from ...auth import AuthUser, get_current_user
from ...redis_client import get_redis
from ...supabase_client import SupabaseAdmin, get_supabase
from .chat import context_key, conversation_title

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/conversations", tags=["conversations"])

LOCAL_MODEL = "jarvis-local"
MAX_AGE = timedelta(days=30)


class LocalExchangeRequest(BaseModel):
    question_id: UUID
    answer_id: UUID
    conversation_id: UUID | None = None
    question: str = Field(min_length=1, max_length=8000)
    answer: str = Field(min_length=1, max_length=8000)
    question_at: datetime | None = None
    answer_at: datetime | None = None


def bounded_time(value: datetime | None, now: datetime) -> datetime:
    """Heure de l'appareil, bornée à [now - 30 j, now] (UTC)."""
    if value is None:
        return now
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    value = value.astimezone(timezone.utc)
    if value > now or value < now - MAX_AGE:
        return now
    return value


@router.post("/local-exchanges", status_code=status.HTTP_201_CREATED)
async def save_local_exchange(
    body: LocalExchangeRequest,
    response: Response,
    user: AuthUser = Depends(get_current_user),
    supabase: SupabaseAdmin = Depends(get_supabase),
    redis: Redis = Depends(get_redis),
) -> dict:
    if body.question_id == body.answer_id:
        raise HTTPException(422, detail="Identifiants identiques")
    user_id = user.id
    question_id, answer_id = str(body.question_id), str(body.answer_id)

    try:
        existing = await supabase.get_message(question_id)
        if existing is not None:
            if existing["user_id"] != user_id:
                raise HTTPException(status.HTTP_409_CONFLICT, detail="Identifiant déjà utilisé")
            response.status_code = status.HTTP_200_OK
            return {
                "conversation_id": existing["conversation_id"],
                "question_id": question_id,
                "answer_id": answer_id,
                "already_saved": True,
            }

        if body.conversation_id is not None:
            conversation = await supabase.get_conversation(str(body.conversation_id), user_id)
            if conversation is None:
                raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Conversation introuvable")
        else:
            conversation = await supabase.create_conversation(user_id, conversation_title(body.question))
        conversation_id = conversation["id"]

        now = datetime.now(timezone.utc)
        question_at = bounded_time(body.question_at, now)
        answer_at = max(bounded_time(body.answer_at, now), question_at)
        try:
            await supabase.insert_messages([
                {
                    "id": question_id,
                    "conversation_id": conversation_id,
                    "user_id": user_id,
                    "role": "user",
                    "content": body.question,
                    "created_at": question_at.isoformat(),
                },
                {
                    "id": answer_id,
                    "conversation_id": conversation_id,
                    "user_id": user_id,
                    "role": "assistant",
                    "content": body.answer,
                    "model": LOCAL_MODEL,
                    "created_at": answer_at.isoformat(),
                },
            ])
        except httpx.HTTPStatusError as exc:
            # Deux envois simultanés du même échange : le premier a gagné.
            if exc.response.status_code != status.HTTP_409_CONFLICT:
                raise
            existing = await supabase.get_message(question_id)
            if existing is None or existing["user_id"] != user_id:
                raise HTTPException(status.HTTP_409_CONFLICT, detail="Identifiant déjà utilisé")
            response.status_code = status.HTTP_200_OK
            return {
                "conversation_id": existing["conversation_id"],
                "question_id": question_id,
                "answer_id": answer_id,
                "already_saved": True,
            }
    except httpx.HTTPError:
        logger.error("Supabase indisponible pour un échange local", exc_info=True)
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, detail="Base de données indisponible")

    # Le contexte court de l'IA sera relu depuis Supabase, dans l'ordre des
    # messages (un échange local peut arriver après coup, hors connexion).
    try:
        await redis.delete(context_key(conversation_id))
    except RedisError:
        logger.warning("Contexte Redis non invalidé", exc_info=True)

    return {
        "conversation_id": conversation_id,
        "question_id": question_id,
        "answer_id": answer_id,
        "already_saved": False,
    }
