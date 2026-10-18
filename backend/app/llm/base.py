"""Contrat commun des fournisseurs de modèles de langage (MIA universel).

Format d'entrée : celui que le backend utilise déjà, une liste de
dictionnaires {"role": "system" | "user" | "assistant", "content": str}.
Chaque adaptateur le convertit lui-même (Claude : instructions système à
part, rôles normalisés ; GroqCloud : format OpenAI, inchangé).

Sortie en flux : une suite d'événements normalisés,
  Texte(texte)                 fragment visible de la réponse (jamais la
                               réflexion interne du modèle) ;
  Fin(raison, usage, modele)   une fois, à la fin normale du flux.
Un refus du modèle n'est PAS une exception dans le flux : le texte déjà
diffusé reste valable pour l'appelant, qui lit `Fin.raison == REFUS`.
Une coupure (réseau, erreur du fournisseur) lève une [ErreurLLM] avec
`apres_texte=True` si du texte est déjà parti.

Sortie JSON : [ReponseJSON] (texte brut, données lues, usage, modèle). Un
refus y lève [Refus] : il n'y a pas de texte partiel utile.

Erreurs : [ErreurLLM] et ses sous-classes portent un `code` et un `message`
identiques à ceux de l'événement SSE `error` actuel (llm_rate_limit,
llm_too_large, llm_auth…) : la route n'a qu'à les recopier.

Rien ici ne connaît FastAPI, Supabase, Redis ni le transport SSE. Les
attentes sur limite de débit restent décidées par l'appelant (les clients
des SDK sont créés sans nouvel essai automatique) ; le flux est un simple
itérateur asynchrone, compatible avec les battements SSE existants.

Outils (appels d'outils, utilisés par ODO) : `flux(..., outils=[DefinitionOutil])`.
Quand le modèle demande des outils, le flux se termine par
`Fin(raison=OUTIL, tour=TourAssistant)` : le tour complet (texte, appels
avec leurs arguments déjà assemblés, blocs bruts du fournisseur à renvoyer
tels quels). La suite de la conversation s'écrit avec deux messages :
  message_appels(tour)                  {"role": "assistant", "content", "tour"}
  message_resultats([ResultatAppel])    {"role": "outil", "content", "resultats"}
Chaque adaptateur les convertit dans le format de son fournisseur. MIA
n'exécute jamais un outil et ne connaît aucune permission (rôle d'ODO).
Sans outils, le comportement est inchangé.
"""

from __future__ import annotations

import json
import re
from abc import ABC, abstractmethod
from collections.abc import AsyncIterator, Mapping, Sequence
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Literal

Message = Mapping[str, Any]
"""{"role": "system" | "user" | "assistant", "content": str}, plus, pour les
outils : {"role": "assistant", "content", "tour": TourAssistant} et
{"role": "outil", "content", "resultats": (ResultatAppel, …)}."""

Effort = Literal["low", "medium", "high", "xhigh", "max"]
EFFORTS: tuple[str, ...] = ("low", "medium", "high", "xhigh", "max")


class RaisonArret(str, Enum):
    FIN = "fin"              # réponse terminée normalement
    LONGUEUR = "longueur"    # plafond de sortie (ou fenêtre du modèle) atteint
    REFUS = "refus"          # le modèle (ou un filtre du fournisseur) a refusé
    OUTIL = "outil"          # le modèle demande un outil (ODO, plus tard)
    AUTRE = "autre"          # raison non reconnue (gardée dans `Fin.detail`)


@dataclass(frozen=True)
class Usage:
    """Tokens d'une requête. `entree` : entrée hors cache ; le cache
    (Claude) est compté à part. `estime` : le fournisseur n'a rien renvoyé."""

    entree: int = 0
    sortie: int = 0
    cache_lecture: int = 0
    cache_ecriture: int = 0
    estime: bool = False

    @property
    def entree_totale(self) -> int:
        return self.entree + self.cache_lecture + self.cache_ecriture

    @property
    def total(self) -> int:
        return self.entree_totale + self.sortie


@dataclass(frozen=True)
class Texte:
    texte: str


@dataclass(frozen=True)
class Fin:
    raison: RaisonArret
    usage: Usage
    modele: str              # modèle qui a réellement répondu
    detail: str | None = None    # raison brute du fournisseur, catégorie de refus…
    tour: "TourAssistant | None" = None   # raison OUTIL : appels demandés

    @property
    def appels(self) -> tuple["AppelOutil", ...]:
        return self.tour.appels if self.tour is not None else ()


Evenement = Texte | Fin


@dataclass(frozen=True)
class ReponseJSON:
    texte: str                               # sortie brute du modèle
    donnees: dict | list | None              # None : JSON illisible
    usage: Usage
    modele: str
    raison: RaisonArret = RaisonArret.FIN


# --- Outils (utilisés par ODO) -----------------------------------------------------

_NOM_OUTIL = re.compile(r"^[a-zA-Z][a-zA-Z0-9_-]{0,63}$")


@dataclass(frozen=True)
class DefinitionOutil:
    nom: str
    description: str
    schema: dict[str, Any]       # JSON Schema d'un objet (arguments)


@dataclass(frozen=True)
class AppelOutil:
    """Appel demandé par le modèle, arguments complets. `erreur_arguments` :
    le modèle a produit des arguments illisibles (jamais exécutés)."""

    id: str
    nom: str
    arguments: dict[str, Any] = field(default_factory=dict)
    erreur_arguments: str | None = None


@dataclass(frozen=True)
class TourAssistant:
    """Réponse du modèle qui demande des outils, à renvoyer telle quelle au
    tour suivant. `brut` : blocs propres au fournisseur (réflexion signée
    de Claude…), jamais affichés ni journalisés."""

    texte: str
    appels: tuple[AppelOutil, ...]
    fournisseur: str
    brut: Any = field(default=None, repr=False, compare=False)


@dataclass(frozen=True)
class ResultatAppel:
    """Résultat d'un appel, renvoyé au modèle (texte déjà préparé par ODO)."""

    id: str
    contenu: str
    erreur: bool = False


def message_appels(tour: TourAssistant) -> dict[str, Any]:
    return {"role": "assistant", "content": tour.texte, "tour": tour}


def message_resultats(resultats: Sequence[ResultatAppel]) -> dict[str, Any]:
    return {"role": "outil", "content": "\n".join(r.contenu for r in resultats), "resultats": tuple(resultats)}


def verifier_outils(outils: Sequence[DefinitionOutil] | None) -> list[DefinitionOutil]:
    """Définitions valides et noms uniques (une erreur de programmation, pas
    du modèle : ValueError)."""
    vus: set[str] = set()
    for o in outils or ():
        if not _NOM_OUTIL.match(o.nom):
            raise ValueError(f"nom d'outil invalide : {o.nom!r}")
        if o.nom in vus:
            raise ValueError(f"outil en double : {o.nom!r}")
        if not isinstance(o.schema, dict) or o.schema.get("type") != "object":
            raise ValueError(f"schéma de l'outil {o.nom!r} : un objet JSON est attendu")
        vus.add(o.nom)
    return list(outils or ())


# --- Erreurs ----------------------------------------------------------------------

MESSAGES = {
    "llm_rate_limit": "Le service IA est très sollicité. Réessaie dans quelques secondes.",
    "llm_credit": "Le service IA est temporairement indisponible (crédit du fournisseur épuisé).",
    "llm_too_large": ("Cette demande dépasse ce que le moteur IA peut traiter en une fois. "
                      "Pose une question plus ciblée (une période, un sujet)."),
    "llm_model": "Le service IA est mal configuré (modèle indisponible).",
    "llm_auth": "Le service IA est mal configuré (clé refusée).",
    "llm_timeout": "Le moteur IA a mis trop de temps à répondre. Réessaie dans un instant.",
    "llm_refus": "Le moteur IA n'a pas pu répondre à cette demande.",
    "llm_unavailable": "Le moteur IA est momentanément indisponible. Réessaie dans un instant.",
}


class ErreurLLM(Exception):
    """Échec d'un fournisseur. `code` / `message` : ceux de l'événement SSE
    `error`. `apres_texte` : du texte avait déjà été diffusé (coupure)."""

    def __init__(self, code: str, *, fournisseur: str, message: str | None = None,
                 apres_texte: bool = False, statut: int | None = None) -> None:
        self.code = code
        self.message = message or MESSAGES.get(code, MESSAGES["llm_unavailable"])
        self.fournisseur = fournisseur
        self.apres_texte = apres_texte
        self.statut = statut
        super().__init__(f"{fournisseur} : {code}")

    def evenement(self) -> dict[str, str]:
        """Charge utile de l'événement SSE `error` (contrat actuel)."""
        return {"code": self.code, "message": self.message}


class LimiteDebit(ErreurLLM):
    """429 (ou surcharge). `attente` : secondes conseillées ; None quand
    attendre ne sert à rien dans la requête (crédit, quota quotidien)."""

    def __init__(self, *, fournisseur: str, attente: float | None, code: str = "llm_rate_limit",
                 message: str | None = None, apres_texte: bool = False, statut: int | None = 429) -> None:
        super().__init__(code, fournisseur=fournisseur, message=message,
                         apres_texte=apres_texte, statut=statut)
        self.attente = attente


class RequeteTropGrande(ErreurLLM):
    """413 ou contexte trop long : l'appelant peut réduire la préparation."""

    def __init__(self, *, fournisseur: str, apres_texte: bool = False, statut: int | None = 413) -> None:
        super().__init__("llm_too_large", fournisseur=fournisseur, apres_texte=apres_texte, statut=statut)


class Refus(ErreurLLM):
    """Le modèle a refusé (sortie JSON seulement ; en flux : Fin.raison)."""

    def __init__(self, *, fournisseur: str, categorie: str | None = None) -> None:
        super().__init__("llm_refus", fournisseur=fournisseur)
        self.categorie = categorie


class ErreurFournisseur(ErreurLLM):
    """Toute autre erreur : clé, modèle, délai, réseau, panne."""


# --- Contrat ----------------------------------------------------------------------

class FournisseurLLM(ABC):
    """Un fournisseur de modèle de langage (Claude, GroqCloud…)."""

    nom: str
    #: La réflexion interne du modèle compte dans le plafond de sortie
    #: (Claude) : l'appelant doit prévoir un plafond plus large.
    reflexion_dans_sortie: bool = False
    #: Budget d'entrée du moteur de compréhension (tokens estimés) propre à
    #: ce fournisseur ; None : réglage commun (calé sur GroqCloud).
    budget_comprehension: int | None = None

    def __init__(self, modele: str) -> None:
        if not modele:
            raise ValueError("modèle non configuré")
        self.modele = modele

    @abstractmethod
    def flux(self, messages: Sequence[Message], *, max_sortie: int, effort: Effort | None = None,
             outils: Sequence[DefinitionOutil] | None = None) -> AsyncIterator[Evenement]:
        """Réponse en flux : des [Texte], puis une [Fin]."""

    @abstractmethod
    async def json(self, messages: Sequence[Message], *, max_sortie: int,
                   schema: dict[str, Any] | None = None, effort: Effort | None = None) -> ReponseJSON:
        """Réponse JSON complète (schéma garanti si le fournisseur le permet)."""

    async def fermer(self) -> None:
        """Libère le client HTTP."""

    def __repr__(self) -> str:      # jamais la clé
        return f"<{type(self).__name__} {self.nom} modele={self.modele!r}>"


async def reponse_complete(llm: FournisseurLLM, messages: Sequence[Message], *, max_sortie: int,
                           effort: Effort | None = None) -> tuple[str, Fin]:
    """Tout le texte d'un flux, et sa fin (essais manuels, scripts)."""
    parts: list[str] = []
    fin = None
    async for e in llm.flux(messages, max_sortie=max_sortie, effort=effort):
        if isinstance(e, Texte):
            parts.append(e.texte)
        else:
            fin = e
    return "".join(parts), fin


# --- Utilitaires partagés par les adaptateurs ----------------------------------

def verifier_messages(messages: Sequence[Message]) -> None:
    if not messages:
        raise ValueError("conversation vide")
    for m in messages:
        role = m.get("role")
        if role not in ("system", "user", "assistant", "outil"):
            raise ValueError(f"rôle inconnu : {role!r}")
        if not isinstance(m.get("content"), str):
            raise ValueError("contenu attendu : du texte")
        if role == "outil":
            resultats = m.get("resultats")
            if not resultats or not all(isinstance(r, ResultatAppel) for r in resultats):
                raise ValueError("message d'outil sans résultats")
        if "tour" in m and (role != "assistant" or not isinstance(m["tour"], TourAssistant)):
            raise ValueError("tour d'outils attendu dans un message assistant")


def estimer_tokens(texte: str) -> int:
    """~4 caractères par token, comme `chat.estimate_tokens`."""
    return max(1, len(texte) // 4) if texte else 0


def lire_json(brut: str) -> dict | list | None:
    """JSON du modèle, toléré entre ``` ou entouré de texte."""
    brut = (brut or "").strip()
    if brut.startswith("```"):
        brut = re.sub(r"^```[a-z]*\s*|\s*```$", "", brut)
    candidats = [brut]
    if "{" in brut:
        candidats.append(brut[brut.find("{"): brut.rfind("}") + 1])
    for candidat in candidats:
        if not candidat:
            continue
        try:
            return json.loads(candidat)
        except ValueError:
            continue
    return None


def secondes(valeur: str | None) -> float | None:
    """« 7.66s », « 1m26.4s », « 450ms », « 12 » → secondes."""
    if not valeur:
        return None
    valeur = valeur.strip()
    try:
        return float(valeur)
    except ValueError:
        pass
    total = 0.0
    for nombre, unite in re.findall(r"([\d.]+)(ms|h|m|s)", valeur):
        total += float(nombre) * {"ms": 0.001, "s": 1, "m": 60, "h": 3600}[unite]
    return total or None


def attente_conseillee(entetes: Mapping[str, str] | None, cles: Sequence[str],
                       defaut: float = 8.0) -> float:
    """Délai d'un 429 lu dans les en-têtes (+0,5 s, 60 s au plus)."""
    entetes = entetes or {}
    for cle in cles:
        delai = secondes(entetes.get(cle))
        if delai is not None:
            return min(delai + 0.5, 60.0)
    return defaut
