"""Contrat commun des outils (compétences) d'ODO.

Un outil déclare ce qu'il fait (nom, description, schéma JSON de ses
arguments), son niveau de sensibilité, et ce qu'il exige (offres
autorisées, connexion externe). Il ne connaît ni le modèle de langage, ni
FastAPI, ni le transport : il reçoit des arguments déjà validés et un
[ContexteOutil] construit par le serveur depuis l'identité VÉRIFIÉE (JWT),
jamais depuis ce que le modèle propose.
"""

from __future__ import annotations

import re
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from enum import Enum
from typing import Any

from ..llm import DefinitionOutil

NOM_OUTIL = re.compile(r"^[a-z][a-z0-9_]{0,63}$")


class Sensibilite(str, Enum):
    LECTURE = "lecture"      # exécutée directement (aucun effet extérieur)
    ACTION = "action"        # préparée, exécutée seulement après confirmation explicite


@dataclass(frozen=True)
class ContexteOutil:
    """Qui demande, et dans quel cadre. Toujours construit par le serveur."""

    user_id: str
    demande_id: str
    plan: str | None = None
    conversation_id: str | None = None
    connexions: frozenset[str] = frozenset()     # services externes connectés (phase 2 : « gmail »)
    a_renouveler: frozenset[str] = frozenset()   # connexions existantes mais à renouveler
    environnement: str = "production"
    #: Décalage horaire de l'appareil (minutes, UTC+1 = 60) : périodes
    #: relatives (« hier ») calculées en heure locale. None : UTC.
    decalage_minutes: int | None = None


@dataclass(frozen=True)
class ResultatOutil:
    """Résultat normalisé. `contenu` : texte destiné au modèle (et à
    l'utilisateur pour une action confirmée) ; `erreur` : code court."""

    contenu: str
    donnees: dict[str, Any] | None = None
    erreur: str | None = None


class Outil(ABC):
    """Une compétence d'ODO. Ajouter un outil = une sous-classe enregistrée
    dans le registre ; l'orchestrateur ne change pas."""

    nom: str
    description: str
    schema: dict[str, Any]
    sensibilite: Sensibilite = Sensibilite.LECTURE
    #: Offres autorisées (None : toutes).
    offres: frozenset[str] | None = None
    #: Connexion externe exigée (phase 2 : « gmail »), None : aucune.
    connexion: str | None = None
    #: Outil de test : jamais proposé en production.
    test_seulement: bool = False
    #: Délai d'exécution propre (secondes) ; None : réglage commun.
    delai: float | None = None
    #: Consigne ajoutée au message système quand l'outil est proposé
    #: (règles de présentation partagées par une famille d'outils).
    consigne: str | None = None

    #: Chemin direct (un seul appel IA) : consigne donnée au modèle à la place
    #: des définitions d'outils quand ODO exécute lui-même l'outil.
    consigne_directe: str | None = None

    def direct(self, question: str) -> dict[str, Any] | None:
        """Arguments si ODO peut exécuter cet outil SANS demander au modèle
        (demande simple et sûre) ; None sinon (chemin habituel)."""
        return None

    @abstractmethod
    async def executer(self, arguments: dict[str, Any], contexte: ContexteOutil) -> ResultatOutil:
        """Exécute l'outil (arguments déjà validés contre `schema`)."""

    def resume(self, arguments: dict[str, Any]) -> str:
        """Phrase décrivant l'action à confirmer (outils sensibles)."""
        return f"Exécuter « {self.nom} »."

    def definition(self) -> DefinitionOutil:
        return DefinitionOutil(nom=self.nom, description=self.description, schema=self.schema)


@dataclass(frozen=True)
class Decision:
    """Réponse de la politique de permissions."""

    autorise: bool
    code: str | None = None
    message: str = ""

    @classmethod
    def oui(cls) -> "Decision":
        return cls(True)

    @classmethod
    def non(cls, code: str, message: str) -> "Decision":
        return cls(False, code, message)


@dataclass
class EtatOutil:
    """Événement non textuel de l'orchestrateur : un outil change d'état."""

    nom: str
    etat: str                      # en_cours | termine | erreur | refuse | confirmation
    code: str | None = None


@dataclass
class DemandeConfirmation:
    """Action sensible préparée, en attente d'une confirmation explicite."""

    id: str
    outil: str
    resume: str
    expire_a: str                  # ISO 8601 (UTC)
    donnees: dict[str, Any] = field(default_factory=dict)
