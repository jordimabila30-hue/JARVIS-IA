"""Registre universel des compétences d'ODO.

Ajouter une compétence : écrire un [Outil] et l'enregistrer (ici, dans
[registre_actif]) ; ni l'orchestrateur ni MIA ne changent. Chaque outil est
contrôlé à l'enregistrement (nom, schéma) : une erreur de déclaration est
vue au démarrage, jamais pendant une conversation.

Production : registre VIDE en phase 1 (les outils fictifs ne sont chargés
que hors production, avec ODO_OUTILS_FICTIFS=true).
"""

from __future__ import annotations

from collections.abc import Iterator

from ..config import Settings
from .contrat import NOM_OUTIL, Outil
from .validation import verifier_schema


class RegistreOutils:
    def __init__(self, outils: list[Outil] | tuple[Outil, ...] = ()) -> None:
        self._outils: dict[str, Outil] = {}
        for o in outils:
            self.enregistrer(o)

    def enregistrer(self, outil: Outil) -> None:
        if not NOM_OUTIL.match(getattr(outil, "nom", "") or ""):
            raise ValueError(f"nom d'outil invalide : {getattr(outil, 'nom', None)!r}")
        if outil.nom in self._outils:
            raise ValueError(f"outil déjà enregistré : {outil.nom!r}")
        if not (outil.description or "").strip():
            raise ValueError(f"outil {outil.nom!r} sans description")
        verifier_schema(outil.schema)
        if outil.schema.get("type") != "object":
            raise ValueError(f"outil {outil.nom!r} : les arguments doivent être un objet")
        self._outils[outil.nom] = outil

    def obtenir(self, nom: str) -> Outil | None:
        return self._outils.get(nom)

    def noms(self) -> list[str]:
        return sorted(self._outils)

    def __iter__(self) -> Iterator[Outil]:
        return iter(self._outils.values())

    def __len__(self) -> int:
        return len(self._outils)


def est_production(settings: Settings) -> bool:
    return settings.environnement.strip().lower() in ("production", "prod")


def registre_actif(settings: Settings) -> RegistreOutils:
    """Outils disponibles pour ce serveur. Phase 1 : aucun outil réel ;
    outils fictifs seulement hors production et sur demande explicite."""
    registre = RegistreOutils()
    if settings.odo_outils_fictifs and not est_production(settings):
        from .outils_fictifs import outils_fictifs
        for outil in outils_fictifs():
            registre.enregistrer(outil)
    return registre
