"""Assemblage d'ODO pour les routes FastAPI.

ODO_ACTIF=false (défaut) : [ServiceODO.execution] renvoie toujours None, la
route de chat garde exactement son comportement actuel (aucun outil
proposé, aucun appel supplémentaire). ODO_ACTIF=true : outils du registre
autorisés pour le compte ; s'il n'y en a aucun, rien ne change non plus.

Indépendant de ABONNEMENTS_ROUTAGE : ODO utilise le fournisseur que la
route a déjà choisi (routage par abonnement ou fournisseur global).
"""

from __future__ import annotations

from collections.abc import Callable

from fastapi import Depends
from redis.asyncio import Redis

from ..config import Settings, get_settings
from ..llm import FournisseurLLM
from ..redis_client import get_redis
from .confirmations import Confirmations
from .contrat import ContexteOutil
from .orchestrateur import ExecutionODO
from .permissions import PolitiqueOutils
from .registre import RegistreOutils, registre_actif

_registres: dict[tuple, RegistreOutils] = {}


def _registre(settings: Settings) -> RegistreOutils:
    """Un registre par configuration (créé une fois, contrôlé à la création)."""
    cle = (settings.odo_outils_fictifs, settings.environnement)
    if cle not in _registres:
        _registres[cle] = registre_actif(settings)
    return _registres[cle]


class ServiceODO:
    def __init__(self, settings: Settings, redis: Redis, registre: RegistreOutils | None = None,
                 politique: PolitiqueOutils | None = None) -> None:
        self.settings = settings
        self.registre = registre if registre is not None else _registre(settings)
        self.politique = politique or PolitiqueOutils()
        self.confirmations = Confirmations(redis, settings.odo_confirmation_ttl)

    @property
    def actif(self) -> bool:
        return bool(self.settings.odo_actif)

    def contexte(self, *, user_id: str, demande_id: str, plan: str | None,
                 conversation_id: str | None = None) -> ContexteOutil:
        # Identité et offre viennent du serveur (JWT, limites effectives) ;
        # connexions externes : aucune en phase 1 (Gmail : phase 2).
        return ContexteOutil(user_id=user_id, demande_id=demande_id, plan=plan,
                             conversation_id=conversation_id, environnement=self.settings.environnement)

    def execution(self, llm: FournisseurLLM, contexte: ContexteOutil,
                  verifier_budget: Callable[[int], str | None] | None = None) -> ExecutionODO | None:
        """Exécution ODO pour cette demande, ou None (ODO inactif ou aucun
        outil autorisé : chemin actuel, inchangé)."""
        if not self.actif:
            return None
        s = self.settings
        execution = ExecutionODO(
            llm=llm, registre=self.registre, politique=self.politique, confirmations=self.confirmations,
            contexte=contexte, max_tours=s.odo_max_tours, max_appels=s.odo_max_appels,
            delai_outil=s.odo_delai_outil, resultat_max=s.odo_resultat_max_caracteres,
            verifier_budget=verifier_budget,
        )
        return execution if execution.actif else None


def get_odo(settings: Settings = Depends(get_settings), redis: Redis = Depends(get_redis)) -> ServiceODO:
    return ServiceODO(settings, redis)
