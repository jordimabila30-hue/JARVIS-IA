"""Corpus pédagogique de Kelasi, chargé par le SERVEUR.

Copie contrôlée de `assets/apprentissage/` (même contenu que l'application,
vérifié par tests/test_apprentissage.py). Le serveur ne fait jamais
confiance à un texte de fiche envoyé par le client : il ne reçoit que des
identifiants et lit ici le contenu, les solutions et les sources.

Fiches autorisées :
- production : seulement les fiches `valide` portant une relecture tracée
  (`validation.par` et `validation.le`) ;
- hors production : aussi les brouillons (contenus de développement).
"""

from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass, field
from functools import lru_cache
from pathlib import Path

DOSSIER = Path(__file__).parent / "corpus"


@dataclass(frozen=True)
class Fiche:
    id: str
    titre: str
    parcours: str
    explication: str
    exemples: tuple[str, ...]
    a_eviter: tuple[str, ...]
    sources: tuple[dict, ...]
    validee: bool


@dataclass(frozen=True)
class Exercice:
    id: str
    fiche: str
    consigne: str
    solution: str
    explication: str


@dataclass(frozen=True)
class Situation:
    id: str
    titre: str
    fiches: tuple[str, ...]
    objectif: str
    consigne: str
    role: str
    ouverture: str


@dataclass
class Corpus:
    version: str              # `version_corpus` du catalogue (comparée à l'appli)
    empreinte: str = ""     # SHA-256 du contenu (information, journaux)
    fiches: dict[str, Fiche] = field(default_factory=dict)
    exercices: dict[str, Exercice] = field(default_factory=dict)
    situations: dict[str, Situation] = field(default_factory=dict)

    def autorisees(self, production: bool) -> dict[str, Fiche]:
        return {i: f for i, f in self.fiches.items() if f.validee or not production}

    def situation_autorisee(self, sid: str, production: bool) -> Situation | None:
        s = self.situations.get(sid)
        autorisees = self.autorisees(production)
        if s is None or not all(f in autorisees for f in s.fiches):
            return None
        return s


def solution(e: dict) -> str:
    """La bonne réponse en clair, calculée d'après le corpus (jamais le client)."""
    t = e["type"]
    if t in ("choix", "meilleur_message", "ecoute"):
        return e["options"][e["bonne"]]
    if t == "vrai_faux":
        return "Vrai" if e["reponse"] else "Faux"
    if t == "trous":
        morceaux = e["texte"].split("___")
        out = morceaux[0]
        for i, trou in enumerate(e["trous"]):
            out += trou["options"][trou["bonne"]] + morceaux[i + 1]
        return out
    if t == "ordre":
        return " / ".join(e["elements"])
    if t == "association":
        return " ; ".join(f"{g} → {d}" for g, d in e["paires"])
    return ""


def _validee(f: dict) -> bool:
    v = f.get("validation") or {}
    return f.get("statut") == "valide" and bool(str(v.get("par", "")).strip()) and bool(v.get("le"))


@lru_cache(maxsize=1)
def charger() -> Corpus:
    fichiers = sorted(DOSSIER.rglob("*.json"))
    empreinte = hashlib.sha256()
    for p in fichiers:
        # Fins de ligne ignorées : même empreinte sous Windows et Linux.
        empreinte.update(p.read_bytes().replace(b"\r\n", b"\n"))
    catalogue = json.loads((DOSSIER / "catalogue.json").read_text(encoding="utf-8"))
    corpus = Corpus(version=str(catalogue.get("version_corpus", "")), empreinte=empreinte.hexdigest()[:12])
    for p in sorted((DOSSIER / "parcours").glob("*.json")):
        j = json.loads(p.read_text(encoding="utf-8"))
        for f in j.get("fiches", []):
            corpus.fiches[f["id"]] = Fiche(
                id=f["id"], titre=f["titre"], parcours=j["parcours"], explication=f["explication"],
                exemples=tuple(f.get("exemples", [])), a_eviter=tuple(f.get("a_eviter", [])),
                sources=tuple(f.get("sources", [])), validee=_validee(f),
            )
        for u in j.get("unites", []):
            for l in u.get("lecons", []):
                for e in l.get("exercices", []):
                    corpus.exercices[e["id"]] = Exercice(
                        id=e["id"], fiche=e["fiche"], consigne=e["consigne"],
                        solution=solution(e), explication=e.get("explication", ""),
                    )
    sit = DOSSIER / "situations.json"
    if sit.exists():
        for s in json.loads(sit.read_text(encoding="utf-8")).get("situations", []):
            corpus.situations[s["id"]] = Situation(
                id=s["id"], titre=s["titre"], fiches=tuple(s["fiches"]), objectif=s["objectif"],
                consigne=s["consigne"], role=s["role"], ouverture=s["ouverture"],
            )
    return corpus
