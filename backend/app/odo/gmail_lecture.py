"""Lecture Gmail (phase 2) : préparer des e-mails COMPRÉHENSIBLES, sans IA.

Le modèle (GroqCloud ou Claude) interprète le sens ; ce module lui donne une
matière fiable, identique pour les deux :

  - nouveau texte séparé du texte CITÉ (« Le … a écrit : », « On … wrote: »,
    lignes « > », « -----Original Message----- », « De : … Envoyé : ») :
    une ancienne information recopiée dans une réponse n'est plus prise pour
    une nouvelle ; le cité est réduit à un court extrait étiqueté ;
  - message transféré étiqueté comme tel (son contenu est gardé) ;
  - date convertie dans l'heure LOCALE de l'utilisateur (`fuseau_minutes`) ;
  - plusieurs e-mails : ordre chronologique, doublons retirés, le plus
    récent indiqué ;
  - repères détectés automatiquement (FR, EN, DE, ES) : demande, échéance,
    simple possibilité, réserve / condition, issue négative, réception,
    changement, expéditeur automatique. Ce sont des INDICES à vérifier dans
    le texte, jamais des conclusions ;
  - pièces jointes : présentes, jamais supposées lues.
Tout le texte passe par `masquer_secrets` (cité et transféré compris).
"""

from __future__ import annotations

import re
from datetime import datetime, timedelta, timezone
from email.utils import parsedate_to_datetime

from ..integrations.gmail import ApercuEmail, Email
from .gmail_confidentialite import masquer_secrets

JOURS = ("lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche")
MOIS = ("janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août", "septembre", "octobre",
        "novembre", "décembre")
CITE_MAX = 300

# --- Texte cité / transféré -------------------------------------------------------------

_ENTETE_CITATION = re.compile(
    r"^\s*(?:(?:le|on|el)\b.{3,200}?(?:a écrit|wrote|escribió)\s*:\s*$|am\b.{3,120}?schrieb\b.{0,120}:\s*$"
    r"|-{2,}\s*(?:original message|message d'origine|ursprüngliche nachricht|mensaje original)\s*-{2,}"
    r"|_{10,}\s*$)", re.I)
_ENTETE_DE = re.compile(r"^\s*(?:de|from|von)\s*:\s*\S", re.I)
_ENTETE_SUITE = re.compile(r"^\s*(?:envoyé|sent|date|gesendet|objet|subject|à|to|an)\s*:", re.I)
_TRANSFERT = re.compile(r"-{2,}\s*(?:forwarded message|message transféré|weitergeleitete nachricht|"
                        r"mensaje reenviado)\s*-{2,}", re.I)


def decouper(texte: str) -> tuple[str, str, str]:
    """(nouveau, cité, transféré) d'un corps d'e-mail."""
    lignes = (texte or "").splitlines()
    transfere = ""
    for i, l in enumerate(lignes):
        if _TRANSFERT.search(l):
            transfere = "\n".join(lignes[i + 1:]).strip()
            lignes = lignes[:i]
            break
    coupe = None
    for i, l in enumerate(lignes):
        paire = l + " " + (lignes[i + 1] if i + 1 < len(lignes) else "")
        if _ENTETE_CITATION.match(l) or _ENTETE_CITATION.match(paire) or \
                (_ENTETE_DE.match(l) and i + 1 < len(lignes) and _ENTETE_SUITE.match(lignes[i + 1])):
            coupe = i
            break
        # Bloc de lignes « > » (au moins 2 d'affilée) : citation.
        if l.lstrip().startswith(">") and i + 1 < len(lignes) and lignes[i + 1].lstrip().startswith(">"):
            coupe = i
            break
    if coupe is None:
        return "\n".join(lignes).strip(), "", transfere
    nouveau = "\n".join(lignes[:coupe]).strip()
    cite = "\n".join(re.sub(r"^\s*>+ ?", "", l) for l in lignes[coupe:]).strip()
    return nouveau, cite, transfere


# --- Dates ------------------------------------------------------------------------------

def date_email(entete: str) -> datetime | None:
    try:
        d = parsedate_to_datetime(entete)
        return d if d.tzinfo else d.replace(tzinfo=timezone.utc)
    except (TypeError, ValueError, IndexError):
        return None


def date_locale(entete: str, decalage_minutes: int | None) -> str:
    """« lundi 19 octobre 2026 à 10:03 (heure de l'utilisateur) » ; l'en-tête
    brut si illisible."""
    d = date_email(entete)
    if d is None:
        return entete or "date inconnue"
    tz = timezone(timedelta(minutes=decalage_minutes or 0))
    local = d.astimezone(tz)
    reference = "heure de l'utilisateur" if decalage_minutes is not None else "UTC"
    return (f"{JOURS[local.weekday()]} {local.day} {MOIS[local.month - 1]} {local.year} à "
            f"{local:%H:%M} ({reference})")


# --- Repères (indices multilingues) --------------------------------------------------------

REPERES: tuple[tuple[str, re.Pattern], ...] = tuple((nom, re.compile(motif, re.I)) for nom, motif in (
    ("issue négative", r"ne (?:pourrons|pouvons|sommes) (?:malheureusement )?pas|pas (?:pu )?(?:donner suite|"
                       r"été retenue?|retenue?)|regrett?ons|malheureusement|unfortunately|regret to|"
                       r"not (?:been )?(?:selected|accepted|successful|approved)|unable to (?:offer|accept)|"
                       r"leider|nicht berücksichtigt|lamentablemente|no ha sido seleccionad"),
    ("réserve / condition", r"sous réserve|à condition|en attente de|sous condition|provisoire|subject to|"
                            r"provided that|pending|conditional|vorbehaltlich|unter vorbehalt|sujeto a"),
    ("demande", r"merci de (?!votre)|veuillez|nous vous (?:prions|demandons) de|vous devez|il (?:vous )?manque|"
                r"(?:est|sont) (?:obligatoire|requis)|please (?!find|note)|kindly|you (?:must|need to|are required "
                r"to)|is required|bitte (?!beachten)|müssen sie|por favor envíe|debe enviar"),
    ("échéance", r"avant le|au plus tard|d'ici (?:le|au|à)|jusqu'au|date limite|no later than|before (?:the )?"
                 r"\d|by (?:monday|tuesday|wednesday|thursday|friday|saturday|sunday|\d)|deadline|due (?:date|by)|"
                 r"bis (?:zum|spätestens)|spätestens|antes del|fecha límite"),
    ("simple possibilité", r"si vous le souhaitez|si vous voulez|vous pouvez(?! pas)|facultati|optionnel|"
                           r"if you (?:wish|like|want)|you (?:may|can) (?!not)|optional|falls sie möchten|"
                           r"können sie gerne|opcional|si lo desea"),
    ("réception", r"bien reçu|avons reçu|accusé de réception|nous accusons|well received|we (?:have )?received|"
                  r"eingegangen|hemos recibido"),
    ("changement", r"report[ée]|décal[ée]|annul[ée]|finalement|modifi[ée]|rectifi|erratum|au lieu de|"
                   r"nouvelle date|nouvel horaire|rescheduled|postponed|cancel+ed|moved to|instead of|"
                   r"verschoben|abgesagt|geändert|stattdessen|aplazad|cancelad|nueva fecha"),
))
_AUTOMATIQUE = re.compile(r"no-?reply|ne-?pas-?repondre|nepasrepondre|mailer-daemon|postmaster|notifications?@|"
                          r"newsletter|donotreply|do-not-reply|automat", re.I)


def expediteur_automatique(de: str) -> bool:
    return bool(_AUTOMATIQUE.search(de or ""))


def _phrase(texte: str, debut: int, fin: int) -> str:
    """Bout de phrase autour d'un repère (≤ 90 caractères)."""
    g = max(texte.rfind(".", 0, debut), texte.rfind("\n", 0, debut)) + 1
    d = min([x for x in (texte.find(".", fin), texte.find("\n", fin)) if x != -1] or [len(texte)])
    morceau = " ".join(texte[g:d].split())
    return morceau if len(morceau) <= 90 else morceau[:87].rstrip() + "…"


def reperes(texte: str, *, avec_phrases: bool = True) -> list[str]:
    """Indices détectés dans le texte NOUVEAU (jamais le cité)."""
    sortie = []
    for nom, motif in REPERES:
        m = motif.search(texte or "")
        if m:
            sortie.append(f"{nom} « {_phrase(texte, m.start(), m.end())} »" if avec_phrases else nom)
    return sortie


# --- Mise en forme pour le modèle ------------------------------------------------------------

def bloc_email(e: Email, maximum: int, decalage_minutes: int | None, rang: str = "") -> str:
    nouveau, cite, transfere = decouper(e.texte)
    nouveau, transfere = masquer_secrets(nouveau), masquer_secrets(transfere)
    lignes = [f"{rang}id={e.id} fil={e.fil}",
              f"De : {e.de}" + (" [expéditeur automatique]" if expediteur_automatique(e.de) else ""),
              f"À : {e.a}", f"Date : {date_locale(e.date, decalage_minutes)}",
              f"Objet : {masquer_secrets(e.objet) or '(sans objet)'}"]
    if e.pieces_jointes:
        lignes.append("Pièces jointes (présentes, contenu NON lu) : " + masquer_secrets(", ".join(e.pieces_jointes)))
    indices = reperes(nouveau + ("\n" + transfere if transfere else ""))
    if indices:
        lignes.append("Repères automatiques (indices à vérifier dans le texte) : " + " ; ".join(indices))
    corps = nouveau[:maximum] + ("\n[… texte coupé]" if len(nouveau) > maximum or e.tronque else "")
    lignes += ["", "Texte de ce message :", corps or "(aucun texte nouveau)"]
    if transfere:
        reste = max(maximum - len(nouveau), maximum // 2)
        lignes += ["", "[Message transféré : son contenu vient d'un autre expéditeur]", transfere[:reste]]
    if cite:
        extrait = masquer_secrets(" ".join(cite.split()))[:CITE_MAX]
        lignes += ["", "[Texte cité d'un message plus ancien : PAS une nouvelle information] " + extrait
                   + ("…" if len(cite) > CITE_MAX else "")]
    return "\n".join(lignes)


def chronologie(emails: list[Email]) -> list[Email]:
    """Du plus ancien au plus récent, sans doublon (même identifiant)."""
    uniques = list({e.id: e for e in emails}.values())
    return sorted(uniques, key=lambda e: date_email(e.date) or datetime.min.replace(tzinfo=timezone.utc))


def dossier(emails: list[Email], maximum: int, decalage_minutes: int | None) -> str:
    """Plusieurs e-mails en ordre chronologique, le plus récent signalé."""
    ordre = chronologie(emails)
    n = len(ordre)
    blocs = []
    for i, e in enumerate(ordre, 1):
        rang = f"Message {i}/{n}" + (" (le plus récent)" if i == n and n > 1 else
                                     " (le plus ancien)" if i == 1 and n > 1 else "") + " · "
        blocs.append(bloc_email(e, maximum, decalage_minutes, rang))
    return "\n\n---\n\n".join(blocs)


def memo_lu(e: ApercuEmail) -> dict[str, str]:
    """Métadonnées d'un e-mail LU, gardées pour les questions de suivi."""
    return {"id": e.id, "fil": e.fil, "de": e.de[:120], "objet": masquer_secrets(e.objet)[:150],
            "date": e.date[:40], "lu": "oui"}
