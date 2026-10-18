"""Images jointes au chat (capture d'écran de JARVIS Touch).

Une image n'est envoyée au modèle que sur action explicite de l'utilisateur
(bouton Envoyer). Règles :

- contrôle AVANT tout appel : format réel (signature des octets, pas le
  type annoncé seul), taille décodée ≤ 5 Mo (limite de l'API Claude),
  dimensions ≤ 8000 px (PNG lu dans son en-tête) ;
- seuls les fournisseurs qui lisent les images (`FournisseurLLM.vision`)
  la reçoivent ; sinon refus clair, avant le quota (jamais d'analyse simulée) ;
- jamais en base : le message enregistre une référence (id, type, taille) ;
  les octets restent dans Redis le temps du contexte court
  (`CHAT_CONTEXT_TTL`, 1 h) pour les questions suivantes sur la même image,
  une seule image par conversation (la dernière) ; ensuite le modèle est
  prévenu que l'image n'est plus disponible ;
- jamais dans les journaux (ni octets, ni base64).
"""

from __future__ import annotations

import base64
import binascii
import json
import logging
import struct
from typing import Any, Literal

from pydantic import BaseModel, Field
from redis.asyncio import Redis
from redis.exceptions import RedisError

logger = logging.getLogger(__name__)

TAILLE_MAX = 5 * 1024 * 1024
COTE_MAX = 8000
# Estimation prudente (Claude réduit l'image à ~1,15 mégapixel ≈ 1 600 tokens).
TOKENS_PAR_IMAGE = 1600
TYPE_PIECE = "capture_ecran"

NOTE_IMAGE_EXPIREE = (
    "[Une capture d'écran était jointe à ce message ; elle n'est plus disponible. "
    "Si la question en dépend, demande à l'utilisateur de la renvoyer.]"
)

VISION_OFFRE = {
    "code": "vision_offre",
    "message": "L’analyse d’image demande l’offre Pro. Votre message n’a pas été envoyé.",
}


class ImageJointe(BaseModel):
    media_type: Literal["image/png", "image/jpeg", "image/webp"]
    # base64 de 5 Mo ≈ 7 Mo de caractères.
    data: str = Field(min_length=16, max_length=7_100_000)


class ImageInvalide(ValueError):
    def detail(self) -> dict[str, str]:
        return {"code": "image_invalide", "message": str(self)}


def _signature(octets: bytes) -> str | None:
    if octets.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    if octets.startswith(b"\xff\xd8\xff"):
        return "image/jpeg"
    if octets[:4] == b"RIFF" and octets[8:12] == b"WEBP":
        return "image/webp"
    return None


def verifier(image: ImageJointe) -> int:
    """Contrôle l'image ; rend sa taille décodée. Lève [ImageInvalide]."""
    try:
        octets = base64.b64decode(image.data, validate=True)
    except (binascii.Error, ValueError):
        raise ImageInvalide("L’image jointe est illisible.") from None
    if not octets:
        raise ImageInvalide("L’image jointe est vide.")
    if len(octets) > TAILLE_MAX:
        raise ImageInvalide("L’image jointe dépasse 5 Mo.")
    if _signature(octets) != image.media_type:
        raise ImageInvalide("Le format de l’image jointe n’est pas reconnu (PNG, JPEG ou WebP).")
    if image.media_type == "image/png" and len(octets) >= 24:
        largeur, hauteur = struct.unpack(">II", octets[16:24])
        if not (0 < largeur <= COTE_MAX and 0 < hauteur <= COTE_MAX):
            raise ImageInvalide("L’image jointe est trop grande (8000 px au plus par côté).")
    return len(octets)


def piece(image_id: str, image: ImageJointe, taille: int) -> dict[str, Any]:
    """Référence enregistrée avec le message (jamais les octets)."""
    return {"type": TYPE_PIECE, "id": image_id, "media_type": image.media_type, "octets": taille}


def image_id_de(attachments: Any) -> str | None:
    """Id de la capture jointe à un message enregistré (ou None)."""
    if isinstance(attachments, list):
        for a in attachments:
            if isinstance(a, dict) and a.get("type") == TYPE_PIECE and a.get("id"):
                return str(a["id"])
    return None


def _cle(conversation_id: str) -> str:
    return f"chat:image:{conversation_id}"


async def garder(redis: Redis, conversation_id: str, image_id: str, image: ImageJointe, ttl: int) -> None:
    """La dernière image de la conversation, le temps du contexte court."""
    try:
        await redis.set(_cle(conversation_id), json.dumps(
            {"id": image_id, "media_type": image.media_type, "data": image.data}), ex=ttl)
    except RedisError:
        logger.warning("Image non gardée pour les questions suivantes (Redis indisponible)")


async def joindre(redis: Redis, conversation_id: str, historique: list[dict]) -> list[dict]:
    """Historique prêt pour le modèle : l'image encore gardée est rattachée
    à son message ; une image expirée devient une note (jamais inventée)."""
    if not any(m.get("image_id") for m in historique):
        return historique
    gardee = None
    try:
        brut = await redis.get(_cle(conversation_id))
        gardee = json.loads(brut) if brut else None
    except (RedisError, ValueError):
        logger.warning("Image gardée illisible (Redis)")
    sortie = []
    for m in historique:
        image_id = m.get("image_id")
        m = {k: v for k, v in m.items() if k != "image_id"}
        if image_id and gardee and gardee.get("id") == image_id:
            m["images"] = [{"media_type": gardee["media_type"], "data": gardee["data"]}]
        elif image_id:
            m["content"] = f"{NOTE_IMAGE_EXPIREE}\n{m['content']}"
        sortie.append(m)
    return sortie
