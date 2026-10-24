"""Chemin direct Gmail (GMAIL 1) : UN seul appel IA pour les demandes simples.

ODO reconnaît, sans IA, une demande Gmail simple et sans ambiguïté
(« résume mes 3 derniers mails », « lis mes mails non lus », « résume le
mail de Lumen », « mes mails de cette semaine »), exécute lui-même la
recherche avec lecture (`gmail_rechercher`, `lire`), puis le modèle reçoit
directement les e-mails et répond : un appel au lieu de deux, sans
définitions d'outils ni consigne de recherche.

Prudence d'abord : toute référence au contexte (« il », « l'autre »,
« celui », « dont », « réponse »…), toute demande longue ou de jugement
(« important », « accepté ? ») passe par le chemin habituel (le modèle
choisit les outils, clarifie si besoin). Si la recherche directe ne trouve
rien de clairement pertinent, le chemin habituel reprend aussi.
"""

from __future__ import annotations

import re
import unicodedata

NOMBRES = {"un": 1, "une": 1, "deux": 2, "trois": 3, "quatre": 4, "cinq": 5, "six": 6, "sept": 7, "huit": 8,
           "neuf": 9, "dix": 10}
PERIODES = {"aujourd'hui": "aujourd_hui", "d'aujourd'hui": "aujourd_hui", "hier": "hier", "d'hier": "hier",
            "cette semaine": "cette_semaine", "de cette semaine": "cette_semaine",
            "la semaine derniere": "semaine_derniere", "de la semaine derniere": "semaine_derniere",
            "ce mois-ci": "ce_mois", "de ce mois-ci": "ce_mois", "du mois": "ce_mois"}

_MAILS = r"(?:e-?mails?|mails?|messages?|courriels?)"
_VERBE = r"(?:resume[rz]?|lis|lire|montre|donne|fais(?:-moi)? un point sur|qu'est-ce que (?:j'ai|disent))"
# Références au contexte ou demandes de jugement : jamais de chemin direct.
_REFUS = re.compile(
    r"\b(?:il|elle|ils|elles|lui|leur|celui|celle|ceux|celles|l'autre|autre|dont|ce mail|ce message|cet e-?mail|"
    r"deuxieme|second|troisieme|precedent|reponse|repondu|important|importants|urgent|accept|refus|pourquoi|"
    r"si |pas |sauf|sans |prof|ecole|dossier|inscription|candidature|concernant|sujet|ou )", re.I)

# « combien de mails non lus ai-je ? » (sans expéditeur, sujet ni période).
_COMPTER = re.compile(
    rf"(?:dis-moi |tu peux me dire |j'ai |est-ce que j'ai )?combien (?:de |d')?(?:{_MAILS} )?non lus?"
    r"(?: (?:ai-je|j'ai|il y a|y a-t-il|me reste-t-il|est-ce que j'ai|en ce moment|actuellement|"
    r"dans (?:ma|la) boite(?: de reception| mail| gmail)?|sur gmail|dans gmail|sur ma boite))*")


def _plat(texte: str) -> str:
    t = unicodedata.normalize("NFD", texte.lower())
    t = "".join(c for c in t if unicodedata.category(c) != "Mn").replace("’", "'")
    t = re.sub(r"^\s*(?:jarvis|hey jarvis|dis jarvis)\s*[,:!]?\s*", "", t)
    t = re.sub(r"\b(?:s'il te plait|stp|svp|rapidement|vite|en bref|brievement|s'il vous plait)\b", " ", t)
    return " ".join(t.replace("?", " ").replace(".", " ").replace("!", " ").split())


def reconnaitre(question: str) -> dict | None:
    """Arguments de `gmail_rechercher` (avec `lire`) si la demande est simple
    et sûre ; sinon None (chemin habituel)."""
    t = _plat(question)
    if _COMPTER.fullmatch(t):
        return {"compter_non_lus": True}
    if not t or len(t.split()) > 12 or _REFUS.search(t + " "):
        return None
    # « résume mes 3 derniers mails », « lis mes derniers messages », « mes mails non lus »
    m = re.fullmatch(rf"(?:{_VERBE} )?(?:mes|les) (?:(\d{{1,2}}|{'|'.join(NOMBRES)}) )?(?:derniers? |nouveaux? )?"
                     rf"{_MAILS}(?: (non lus|recus))?(?: ((?:d'|de |du |de la |la |ce |cette ).+))?", t)
    if m:
        nombre, non_lus, suite = m.group(1), m.group(2), m.group(3)
        if not re.match(rf"{_VERBE}", t) and not non_lus and not suite:
            return None                       # « mes mails » seul : demande trop vague
        args: dict = {"lire": True}
        if nombre:
            n = int(nombre) if nombre.isdigit() else NOMBRES[nombre]
            if not 1 <= n <= 10:
                return None
            args["max"] = n
        if non_lus == "non lus":
            args["non_lus"] = True
        if suite:
            if suite not in PERIODES:
                return None                   # autre complément (expéditeur, sujet…) : chemin habituel
            args["periode"] = PERIODES[suite]
        return args
    # « résume le (dernier) mail de Lumen » : expéditeur nommé explicitement (1 à 3 mots).
    m = re.fullmatch(rf"{_VERBE} (?:le|les) (?:(\d{{1,2}}|{'|'.join(NOMBRES)}) )?(?:derniers? )?{_MAILS} "
                     r"(?:de la |de l'|du |des |de |d')([a-z0-9][a-z0-9.@'-]*(?: [a-z0-9.@'-]+){0,2})", t)
    if m:
        nom = m.group(2)
        if nom in PERIODES or nom.split()[0] in ("cette", "ce", "hier", "aujourd'hui", "la"):
            return None
        args = {"lire": True, "expediteurs": [nom], "max": 1}
        if m.group(1):
            n = int(m.group(1)) if m.group(1).isdigit() else NOMBRES[m.group(1)]
            if not 1 <= n <= 10:
                return None
            args["max"] = n
        return args
    # « résume le fil / le mail / la discussion sur la réunion de projet » : sujet explicite (1 à 5 mots).
    m = re.fullmatch(rf"{_VERBE} (?:le|la) (?:dernier |derniere )?(?:fil|discussion|conversation|{_MAILS}) "
                     r"(?:sur|a propos de) (?:le |la |les |l'|mon |ma |mes )?([a-z0-9'-]+(?: [a-z0-9'-]+){0,4})", t)
    if m:
        mots = [x for x in re.split(r"[ ']", m.group(1)) if len(x) > 2 and x not in ("des", "les", "pour", "avec")]
        return {"lire": True, "termes": [" ".join(mots)] + mots[:4], "max": 1} if mots else None
    return None
