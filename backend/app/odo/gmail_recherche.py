"""Recherche Gmail intelligente (phase 1) : partie DÉTERMINISTE.

Le modèle (GroqCloud ou Claude, via MIA) comprend la demande et remplit des
critères structurés dans UN seul appel d'outil : expéditeurs possibles,
termes ET reformulations probables, période nommée… Tout le reste est
calculé ici, à l'identique pour les deux fournisseurs :

  - périodes relatives (« hier », « cette semaine ») dans le FUSEAU de
    l'utilisateur, envoyées à Gmail en secondes (after:/before: epoch) ;
  - requête Gmail : alternatives en OU ({…}), variantes sans accents,
    jamais une chaîne libre du modèle ;
  - élargissement progressif borné ([PLAN] : 3 requêtes Gmail au plus),
    seulement si l'étape précédente ne trouve rien ;
  - classement par pertinence (objet, expéditeur, extrait, récence) : un
    message qui ne partage qu'un mot avec la demande est « faible » ;
  - regroupement par fil ; expéditeurs distincts signalés (clarification) ;
  - compte rendu de ce qui a été CONSULTÉ (jamais « aucun e-mail n'existe »).
"""

from __future__ import annotations

import re
import unicodedata
from dataclasses import dataclass, field, replace
from datetime import date, datetime, time, timedelta, timezone
from email.utils import parsedate_to_datetime

from ..integrations.gmail import ApercuEmail, valeur_requete

PERIODES = ("aujourd_hui", "hier", "cette_semaine", "semaine_derniere", "ce_mois", "mois_dernier",
            "7_jours", "30_jours", "90_jours", "cette_annee")
LIBELLES_PERIODES = {
    "aujourd_hui": "aujourd'hui", "hier": "hier", "cette_semaine": "cette semaine",
    "semaine_derniere": "la semaine dernière", "ce_mois": "ce mois-ci", "mois_dernier": "le mois dernier",
    "7_jours": "les 7 derniers jours", "30_jours": "les 30 derniers jours", "90_jours": "les 3 derniers mois",
    "cette_annee": "cette année",
}

#: Mots trop vagues pour juger la pertinence (la recherche Gmail les garde).
_VIDES = {"mail", "mails", "email", "emails", "message", "messages", "courriel", "reponse", "repondu", "objet",
          "bonjour", "merci", "pour", "dans", "avec", "votre", "vous", "mon", "mes", "les", "des", "une"}


def sans_accents(texte: str) -> str:
    return "".join(c for c in unicodedata.normalize("NFD", texte) if unicodedata.category(c) != "Mn")


def _racines(texte: str) -> set[str]:
    """Racines comparables (minuscules, sans accents, 5 premières lettres)."""
    mots = re.findall(r"[a-z0-9]{3,}", sans_accents(texte.lower()))
    return {m[:5] for m in mots if m not in _VIDES}


# --- Périodes ---------------------------------------------------------------------

def _fuseau(decalage_minutes: int | None) -> timezone:
    return timezone(timedelta(minutes=decalage_minutes or 0))


def bornes_periode(periode: str, maintenant: datetime, decalage_minutes: int | None) -> tuple[datetime, datetime]:
    """[début, fin[ en UTC d'une période nommée, calculée en heure LOCALE de
    l'utilisateur (semaine du lundi au dimanche)."""
    tz = _fuseau(decalage_minutes)
    local = maintenant.astimezone(tz)
    jour = datetime.combine(local.date(), time(), tz)
    lundi = jour - timedelta(days=local.weekday())
    premier = jour.replace(day=1)
    match periode:
        case "aujourd_hui":
            debut, fin = jour, jour + timedelta(days=1)
        case "hier":
            debut, fin = jour - timedelta(days=1), jour
        case "cette_semaine":
            debut, fin = lundi, jour + timedelta(days=1)
        case "semaine_derniere":
            debut, fin = lundi - timedelta(days=7), lundi
        case "ce_mois":
            debut, fin = premier, jour + timedelta(days=1)
        case "mois_dernier":
            debut, fin = (premier - timedelta(days=1)).replace(day=1), premier
        case "7_jours" | "30_jours" | "90_jours":
            debut, fin = jour - timedelta(days=int(periode.split("_")[0]) - 1), jour + timedelta(days=1)
        case "cette_annee":
            debut, fin = jour.replace(month=1, day=1), jour + timedelta(days=1)
        case _:
            raise ValueError(periode)
    return debut.astimezone(timezone.utc), fin.astimezone(timezone.utc)


def bornes_dates(depuis: date | None, jusqua: date | None,
                 decalage_minutes: int | None) -> tuple[datetime | None, datetime | None]:
    """Dates explicites (incluses), en jours locaux de l'utilisateur."""
    tz = _fuseau(decalage_minutes)
    debut = datetime.combine(depuis, time(), tz).astimezone(timezone.utc) if depuis else None
    fin = (datetime.combine(jusqua + timedelta(days=1), time(), tz).astimezone(timezone.utc)
           if jusqua else None)
    return debut, fin


# --- Critères et requête ----------------------------------------------------------

def _alternatives(valeurs: list[str] | None, limite: int) -> list[str]:
    """Valeurs sûres, sans doublon, avec leur variante sans accents."""
    sortie: list[str] = []
    for v in valeurs or []:
        propre = valeur_requete(v)[:60]
        for x in (propre, sans_accents(propre)):
            if x and x.lower() not in {s.lower() for s in sortie}:
                sortie.append(x)
    return sortie[:limite]


def _groupe(operateur: str, valeurs: list[str]) -> str:
    morceaux = [f'{operateur}"{v}"' for v in valeurs]
    return morceaux[0] if len(morceaux) == 1 else "{" + " ".join(morceaux) + "}"


@dataclass(frozen=True)
class Criteres:
    expediteurs: list[str] = field(default_factory=list)       # l'un OU l'autre
    destinataire: str | None = None
    objet: list[str] = field(default_factory=list)             # l'un OU l'autre, dans l'objet
    termes: list[str] = field(default_factory=list)            # l'un OU l'autre, n'importe où
    debut: datetime | None = None                              # UTC, inclus
    fin: datetime | None = None                                # UTC, exclu
    non_lus: bool = False
    importants: bool = False
    pieces_jointes: bool = False
    envoyes: bool = False
    libelle_periode: str | None = None

    @classmethod
    def depuis_arguments(cls, a: dict, maintenant: datetime, decalage_minutes: int | None) -> "Criteres":
        if a.get("periode"):
            debut, fin = bornes_periode(a["periode"], maintenant, decalage_minutes)
            libelle = LIBELLES_PERIODES[a["periode"]]
        else:
            depuis = date.fromisoformat(a["depuis"]) if a.get("depuis") else None
            jusqua = date.fromisoformat(a["jusqua"]) if a.get("jusqua") else None
            debut, fin = bornes_dates(depuis, jusqua, decalage_minutes)
            libelle = " ".join(x for x in (f"depuis le {depuis:%d/%m/%Y}" if depuis else "",
                                           f"jusqu'au {jusqua:%d/%m/%Y}" if jusqua else "") if x) or None
        return cls(
            expediteurs=_alternatives(a.get("expediteurs"), 6),
            destinataire=valeur_requete(a["destinataire"])[:60] if a.get("destinataire") else None,
            objet=_alternatives([a["objet"]] if a.get("objet") else [], 2),
            termes=_alternatives(a.get("termes"), 12),
            debut=debut, fin=fin, non_lus=bool(a.get("non_lus")), importants=bool(a.get("importants")),
            pieces_jointes=bool(a.get("pieces_jointes")), envoyes=bool(a.get("envoyes")),
            libelle_periode=libelle)

    def requete(self) -> str:
        """Requête Gmail (`q`). Sans critère : messages reçus récents."""
        m: list[str] = []
        if self.expediteurs:
            m.append(_groupe("from:", self.expediteurs))
        if self.destinataire:
            m.append(f'to:"{self.destinataire}"')
        if self.objet:
            m.append(_groupe("subject:", self.objet))
        if self.termes:
            m.append(_groupe("", self.termes))
        if self.debut:
            m.append(f"after:{int(self.debut.timestamp())}")
        if self.fin:
            m.append(f"before:{int(self.fin.timestamp())}")
        if self.pieces_jointes:
            m.append("has:attachment")
        if self.non_lus:
            m.append("is:unread")
        if self.importants:
            m.append("is:important")
        if self.envoyes:
            m.append("in:sent")
        return " ".join(m) or "in:inbox"

    def description(self) -> str:
        """Ce qui a été cherché, en clair (pour le modèle et l'utilisateur)."""
        d = []
        if self.expediteurs:
            d.append("de " + " ou ".join(self.expediteurs[:3]))
        if self.destinataire:
            d.append(f"à {self.destinataire}")
        if self.objet:
            d.append("objet « " + " / ".join(self.objet[:2]) + " »")
        if self.termes:
            d.append("mots : " + ", ".join(self.termes[:8]))
        if self.libelle_periode:
            d.append(self.libelle_periode)
        if self.pieces_jointes:
            d.append("avec pièce jointe")
        if self.non_lus:
            d.append("non lus")
        if self.importants:
            d.append("marqués importants")
        if self.envoyes:
            d.append("envoyés")
        return ", ".join(d) or "messages récents"


def plan(c: Criteres) -> list[tuple[str, Criteres]]:
    """Étapes de recherche, de la plus stricte à la plus large. La suivante
    ne sert que si la précédente ne trouve rien. Jamais deux requêtes
    identiques ; jamais plus de 3."""
    etapes = [("stricte", c)]
    if c.objet:
        # Les mots de l'objet peuvent figurer ailleurs (corps, autre formulation).
        etapes.append(("objet élargi au texte", replace(c, objet=[], termes=_alternatives(c.objet + c.termes, 12))))
    elif c.termes and c.expediteurs:
        # Bon expéditeur, autres mots : tous ses messages de la période.
        etapes.append(("tous les messages de l'expéditeur", replace(c, termes=[])))
    if (c.non_lus or c.importants) and (c.termes or c.expediteurs or c.objet):
        etapes.append(("sans filtre lus / importants", replace(etapes[-1][1], non_lus=False, importants=False)))
    vues, uniques = set(), []
    for nom, crit in etapes:
        if crit.requete() not in vues:
            vues.add(crit.requete())
            uniques.append((nom, crit))
    return uniques[:3]


# --- Pertinence ----------------------------------------------------------------------

@dataclass
class Candidat:
    email: ApercuEmail
    score: float
    pertinence: str                  # forte | moyenne | faible
    raisons: list[str]
    dans_fil: int = 1                # messages de ce fil parmi les résultats


def _date(e: ApercuEmail) -> datetime | None:
    try:
        d = parsedate_to_datetime(e.date)
        return d if d.tzinfo else d.replace(tzinfo=timezone.utc)
    except (TypeError, ValueError, IndexError):
        return None


def _adresse(de: str) -> str:
    m = re.search(r"<([^>]+)>", de)
    return (m.group(1) if m else de).strip().lower()


def classer(emails: list[ApercuEmail], c: Criteres, maintenant: datetime) -> list[Candidat]:
    """Score déterministe : un mot de la demande dans l'objet compte plus que
    dans l'extrait ; l'expéditeur demandé compte beaucoup ; la récence
    départage. Un fil = un candidat (le plus pertinent, puis le plus récent)."""
    cherches = _racines(" ".join(c.termes + c.objet))
    expediteurs = [_racines(x) for x in c.expediteurs]
    candidats: list[Candidat] = []
    for e in emails:
        raisons, score = [], 0.0
        objet, extrait, de = _racines(e.objet), _racines(e.extrait), _racines(e.de)
        if cherches:
            dans_objet = cherches & objet
            dans_extrait = (cherches & extrait) - dans_objet
            if dans_objet:
                score += 3 * len(dans_objet)
                raisons.append("objet")
            if dans_extrait:
                score += len(dans_extrait)
                raisons.append("texte")
        if expediteurs and any(x & (de | _racines(_adresse(e.de))) for x in expediteurs if x):
            score += 3
            raisons.append("expéditeur")
        d = _date(e)
        if d is not None:
            age = max((maintenant - d).total_seconds() / 86400, 0)
            score += max(0.0, 1 - age / 30)         # bonus de récence (≤ 1)
        if not cherches and not expediteurs:
            pertinence = "moyenne"                   # recherche par période / statut seulement
        elif ("objet" in raisons and (not expediteurs or "expéditeur" in raisons)) or \
                ("expéditeur" in raisons and ("texte" in raisons or not cherches)):
            pertinence = "forte"
        elif raisons:
            pertinence = "moyenne"
        else:
            pertinence = "faible"                    # trouvé par Gmail, rien de visible en commun
        candidats.append(Candidat(e, score, pertinence, raisons))
    candidats.sort(key=lambda x: (x.score, _date(x.email) or datetime.min.replace(tzinfo=timezone.utc)),
                   reverse=True)
    par_fil: dict[str, Candidat] = {}
    for x in candidats:
        if x.email.fil in par_fil:
            par_fil[x.email.fil].dans_fil += 1
        else:
            par_fil[x.email.fil] = x
    return list(par_fil.values())


def expediteurs_distincts(candidats: list[Candidat]) -> list[str]:
    vus: dict[str, str] = {}
    for x in candidats:
        if x.pertinence != "faible":
            vus.setdefault(_adresse(x.email.de), x.email.de)
    return list(vus.values())
