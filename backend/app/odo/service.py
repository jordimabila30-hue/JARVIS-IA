"""Assemblage d'ODO pour les routes FastAPI.

ODO_ACTIF=false (défaut) : [ServiceODO.execution] renvoie toujours None, la
route de chat garde exactement son comportement actuel (aucun outil
proposé, aucun appel supplémentaire). ODO_ACTIF=true : outils du registre
autorisés pour le compte ; s'il n'y en a aucun, rien ne change non plus
(sauf une courte note au modèle quand une compétence existe mais que le
compte ne l'a pas connectée : « connectez Gmail dans Paramètres »).

Indépendant de ABONNEMENTS_ROUTAGE : ODO utilise le fournisseur que la
route a déjà choisi (routage par abonnement ou fournisseur global).
"""

from __future__ import annotations

from collections.abc import Callable

from fastapi import Depends
from redis.asyncio import Redis

from ..config import Settings, get_settings
from ..integrations import google as google_mod
from ..llm import FournisseurLLM
from ..redis_client import get_redis
from .confirmations import Confirmations
from .contrat import ContexteOutil
from .orchestrateur import ExecutionODO
from .permissions import PolitiqueOutils
from .registre import RegistreOutils, registre_actif

_registres: dict[tuple, RegistreOutils] = {}

NOMS_CONNEXIONS = {"gmail": "Gmail"}


def _registre(settings: Settings, google=None) -> RegistreOutils:
    """Un registre par configuration (créé une fois, contrôlé à la création)."""
    cle = (settings.odo_outils_fictifs, settings.environnement, id(google) if google else None,
           bool(google and google.configure))
    if cle not in _registres:
        _registres[cle] = registre_actif(settings, google)
    return _registres[cle]


class ServiceODO:
    def __init__(self, settings: Settings, redis: Redis, registre: RegistreOutils | None = None,
                 politique: PolitiqueOutils | None = None, google=None) -> None:
        self.settings = settings
        self.google = google
        self.registre = registre if registre is not None else _registre(settings, google)
        self.politique = politique or PolitiqueOutils()
        self.confirmations = Confirmations(redis, settings.odo_confirmation_ttl)

    @property
    def actif(self) -> bool:
        return bool(self.settings.odo_actif)

    def contexte(self, *, user_id: str, demande_id: str, plan: str | None,
                 conversation_id: str | None = None, connexions: frozenset[str] = frozenset(),
                 a_renouveler: frozenset[str] = frozenset()) -> ContexteOutil:
        # Identité et offre viennent du serveur (JWT, limites effectives).
        return ContexteOutil(user_id=user_id, demande_id=demande_id, plan=plan,
                             conversation_id=conversation_id, connexions=connexions,
                             a_renouveler=a_renouveler, environnement=self.settings.environnement)

    def _connexions_utiles(self) -> set[str]:
        return {o.connexion for o in self.registre if o.connexion}

    async def contexte_compte(self, *, user_id: str, demande_id: str, plan: str | None,
                              conversation_id: str | None = None) -> ContexteOutil:
        """Contexte avec l'état réel des connexions externes du compte (lu
        seulement si une compétence en dépend)."""
        connexions, a_renouveler = set(), set()
        if "gmail" in self._connexions_utiles() and self.google is not None:
            try:
                statut = await self.google.statut(user_id)
            except Exception:               # noqa: BLE001 : base indisponible → Gmail non proposé
                statut = None
            if statut == "active":
                connexions.add("gmail")
            elif statut == "a_renouveler":
                a_renouveler.add("gmail")
        return self.contexte(user_id=user_id, demande_id=demande_id, plan=plan, conversation_id=conversation_id,
                             connexions=frozenset(connexions), a_renouveler=frozenset(a_renouveler))

    def note(self, contexte: ContexteOutil) -> str | None:
        """Consigne courte pour une compétence existante mais non connectée
        (jamais d'outil proposé dans ce cas)."""
        if not self.actif:
            return None
        manquantes = sorted(c for c in self._connexions_utiles() if c not in contexte.connexions)
        notes = []
        for c in manquantes:
            nom = NOMS_CONNEXIONS.get(c, c)
            if c in contexte.a_renouveler:
                notes.append(f"La connexion {nom} de l'utilisateur doit être renouvelée : s'il demande ses "
                             f"e-mails, dis-lui simplement de reconnecter {nom} dans Paramètres › {nom}. "
                             "N'invente aucun e-mail.")
            else:
                notes.append(f"{nom} n'est pas connecté pour ce compte : si l'utilisateur demande ses e-mails, "
                             f"dis-lui simplement de connecter {nom} dans Paramètres › {nom}. N'invente aucun e-mail.")
        return "\n".join(notes) or None

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


def _google_ou_rien():
    try:
        return google_mod.get_google()
    except RuntimeError:
        return None


def get_odo(settings: Settings = Depends(get_settings), redis: Redis = Depends(get_redis)) -> ServiceODO:
    return ServiceODO(settings, redis, google=_google_ou_rien())
