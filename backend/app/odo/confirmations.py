"""Confirmations des actions sensibles (Redis).

Une action sensible n'est JAMAIS exécutée dans la demande où le modèle la
propose : ODO la prépare ici (outil, arguments validés, compte, échéance),
et seule une nouvelle requête authentifiée du même compte peut la
consommer, une fois :
  odo:confirmation:{user_id}:{id}   JSON, TTL = ODO_CONFIRMATION_TTL
La clé contient le compte : un autre compte ne peut ni la lire ni la
consommer. Consommation par GETDEL (atomique) : deux confirmations
simultanées n'exécutent l'action qu'une seule fois. Sans Redis : aucune
action n'est préparée (fermé par défaut).
"""

from __future__ import annotations

import json
import secrets
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any

from redis.asyncio import Redis

from .contrat import ContexteOutil, DemandeConfirmation, Outil


def cle(user_id: str, confirmation_id: str) -> str:
    return f"odo:confirmation:{user_id}:{confirmation_id}"


@dataclass(frozen=True)
class ActionEnAttente:
    id: str
    outil: str
    arguments: dict[str, Any]
    demande_id: str
    conversation_id: str | None


class Confirmations:
    def __init__(self, redis: Redis, ttl: int) -> None:
        self._redis = redis
        self._ttl = ttl

    async def preparer(self, outil: Outil, arguments: dict[str, Any], contexte: ContexteOutil) -> DemandeConfirmation:
        identifiant = secrets.token_urlsafe(18)
        expire = datetime.now(timezone.utc) + timedelta(seconds=self._ttl)
        await self._redis.set(cle(contexte.user_id, identifiant), json.dumps({
            "outil": outil.nom, "arguments": arguments,
            "demande_id": contexte.demande_id, "conversation_id": contexte.conversation_id,
        }, ensure_ascii=False), ex=self._ttl, nx=True)
        return DemandeConfirmation(id=identifiant, outil=outil.nom, resume=outil.resume(arguments),
                                   expire_a=expire.replace(microsecond=0).isoformat())

    async def consommer(self, user_id: str, confirmation_id: str) -> ActionEnAttente | None:
        """L'action préparée pour CE compte, retirée (usage unique) ; None :
        inconnue, expirée, déjà utilisée ou d'un autre compte."""
        brut = await self._redis.getdel(cle(user_id, confirmation_id))
        if not brut:
            return None
        d = json.loads(brut)
        return ActionEnAttente(id=confirmation_id, outil=d["outil"], arguments=d["arguments"],
                               demande_id=d.get("demande_id") or "", conversation_id=d.get("conversation_id"))
