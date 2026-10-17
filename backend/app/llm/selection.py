"""Choix du fournisseur de modèle de langage (MIA universel).

Par défaut : `LLM_PROVIDER` (anthropic si absent). Un nom explicite
(`creer("groq")`) sert aux tests et aux comparaisons : ce module n'est PAS
une API utilisateur. En phase 2, seule la route décidera d'accepter un
autre fournisseur (environnement de test autorisé, compte administrateur).

Un fournisseur inconnu → [FournisseurInconnu] ; connu mais incomplet (clé
ou modèle absent) → [FournisseurNonConfigure], qui nomme la variable
manquante, jamais sa valeur. Aucun repli automatique vers un autre
fournisseur.

Ajouter un fournisseur : une fabrique dans [FABRIQUES] (un fichier par
adaptateur, importé ici à la demande).
"""

from __future__ import annotations

from collections.abc import Callable

from ..config import Settings, get_settings
from .base import EFFORTS, FournisseurLLM

FOURNISSEUR_DEFAUT = "anthropic"


class FournisseurInconnu(ValueError):
    pass


class FournisseurNonConfigure(RuntimeError):
    pass


def _exiger(valeur: str | None, variable: str, nom: str) -> str:
    valeur = (valeur or "").strip()
    if not valeur:
        raise FournisseurNonConfigure(f"Fournisseur « {nom} » non configuré : {variable} manquant.")
    return valeur


def _anthropic(settings: Settings, modele: str | None = None) -> FournisseurLLM:
    from .anthropic import FournisseurAnthropic

    effort = (settings.anthropic_effort or "").strip().lower() or None
    if effort is not None and effort not in EFFORTS:
        raise FournisseurNonConfigure(
            f"Fournisseur « anthropic » mal configuré : ANTHROPIC_EFFORT doit valoir {', '.join(EFFORTS)}.")
    return FournisseurAnthropic(
        cle=_exiger(settings.anthropic_api_key, "ANTHROPIC_API_KEY", "anthropic"),
        modele=_exiger(modele or settings.anthropic_model, "ANTHROPIC_MODEL", "anthropic"),
        effort=effort,
        budget_comprehension=settings.anthropic_comprehension_budget_tokens,
    )


def _groq(settings: Settings, modele: str | None = None) -> FournisseurLLM:
    from .groq import FournisseurGroq

    return FournisseurGroq(
        cle=_exiger(settings.openai_api_key, "OPENAI_API_KEY", "groq"),
        modele=_exiger(modele or settings.openai_model, "OPENAI_MODEL", "groq"),
        base_url=settings.openai_base_url,
    )


# fabrique(settings, modele) : modele None = modèle de la configuration.
FABRIQUES: dict[str, Callable[..., FournisseurLLM]] = {
    "anthropic": _anthropic,
    "groq": _groq,
}

_MODELES_CONFIGURES = {"anthropic": "anthropic_model", "groq": "openai_model"}


def nom_configure(settings: Settings | None = None) -> str:
    settings = settings or get_settings()
    return (settings.llm_provider or FOURNISSEUR_DEFAUT).strip().lower() or FOURNISSEUR_DEFAUT


def modele_configure(nom: str, settings: Settings | None = None) -> str | None:
    """Modèle de la configuration (.env) pour [nom]."""
    settings = settings or get_settings()
    attribut = _MODELES_CONFIGURES.get(nom)
    return getattr(settings, attribut, None) if attribut else None


def creer(nom: str | None = None, settings: Settings | None = None, modele: str | None = None) -> FournisseurLLM:
    """Nouveau fournisseur [nom] (celui de la configuration si None), avec
    [modele] (abonnement) ou celui de la configuration."""
    settings = settings or get_settings()
    nom = (nom or nom_configure(settings)).strip().lower()
    fabrique = FABRIQUES.get(nom)
    if fabrique is None:
        raise FournisseurInconnu(
            f"Fournisseur inconnu : « {nom} » (connus : {', '.join(sorted(FABRIQUES))}).")
    return fabrique(settings, (modele or "").strip() or None)


def choix_manuel_possible(settings: Settings | None = None) -> bool:
    """Le choix manuel d'un fournisseur est-il ouvert (tests) ? Jamais en
    production ; la route vérifie en plus le compte (LLM_ADMINS)."""
    settings = settings or get_settings()
    return settings.llm_selection_manuelle and settings.environnement.strip().lower() not in ("production", "prod")


def configures(settings: Settings | None = None) -> dict[str, bool]:
    """Fournisseur → configuré ? (supervision, console ; aucune valeur)."""
    settings = settings or get_settings()
    etat = {}
    for nom in FABRIQUES:
        try:
            creer(nom, settings)
            etat[nom] = True
        except FournisseurNonConfigure:
            etat[nom] = False
    return etat


# Une instance par fournisseur, pour toute la durée du processus.
_instances: dict[str, FournisseurLLM] = {}


def fournisseur(nom: str | None = None, settings: Settings | None = None,
                modele: str | None = None) -> FournisseurLLM:
    """Instance partagée du fournisseur [nom] (celui de la configuration si
    None) et du [modele] (abonnement ; None : celui de la configuration),
    créée au premier appel avec [settings]. Une instance par couple."""
    nom = (nom or nom_configure(settings)).strip().lower()
    modele = (modele or "").strip() or None
    cle = nom if modele is None else f"{nom}:{modele}"
    if cle not in _instances:
        _instances[cle] = creer(nom, settings, modele)
    return _instances[cle]


async def fermer_tous() -> None:
    while _instances:
        _, instance = _instances.popitem()
        await instance.fermer()
