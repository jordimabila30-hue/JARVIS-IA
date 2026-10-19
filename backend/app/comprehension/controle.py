"""Contrôles DÉTERMINISTES de la compréhension partagée et des propositions.

Vu en réel (2026-10-19, « annonce grave ») : la lecture commune écrite par
la réponse principale (« proposer ton soutien ou une alternative ») a été
présentée aux lots comme une consigne ; plusieurs tons ont alors proposé
« je peux prendre ta place à l'escalade », que rien dans les messages ne
justifiait. Une interprétation fragile contaminait les 36 propositions.

Deux contrôles, sans appel IA, confrontés aux VRAIS messages :

  1. avant la génération, `nettoyer_interpretation` : la lecture commune
     (et l'analyse redonnée aux lots) est découpée en propositions ;
     chacune est confrontée aux messages récents : initiative sans
     justification, participant absent de l'échange, citation introuvable,
     date ou heure absente des messages, décision non écrite, humour dans
     une situation grave → retirée ; certitude excessive → nuancée. Les
     faits restent ; l'interprétation qui survit est transmise comme une
     PISTE, jamais comme une consigne ;
  2. après la génération, `Controle.examiner` : chaque proposition est
     refusée si elle prend un engagement que les messages ne justifient
     pas (remplacer quelqu'un, venir, promettre, appeler un tiers, fixer
     un rendez-vous), invente une date ou une heure, ou plaisante dans une
     situation grave. Seule la combinaison concernée est redemandée
     (generation.completer) ; les propositions valides sont gardées.

Les engagements ne sont pas interdits : ils passent quand les messages ou
la demande de l'utilisateur les justifient (« tu peux venir ? »).
"""

import re
from dataclasses import dataclass, field

from .extraits import _RIRES, ContexteJoint, MessageSource, texte_affiche
from .reperes import normaliser

MESSAGES_SOURCES = 30        # messages récents confrontés aux propositions
MESSAGES_LECTURE = 10        # échange récent confronté à la lecture
MESSAGES_ENGAGEMENT = 8      # un engagement doit être justifié par l'échange RÉCENT

# Engagement pris à la place de l'utilisateur → mots qui, dans les messages
# ou la demande, le justifient. Texte normalisé (minuscules, sans accents).
ENGAGEMENTS: list[tuple[str, re.Pattern, re.Pattern]] = [
    ("remplacer quelqu'un",
     re.compile(r"\b(?:prendre|prends|prenne|prendrai) (?:ta|sa|votre|leur) place\b|\bte remplacer\b|"
                r"\bje (?:te |le |la )?remplace\b|\ba ta place\b|\bje (?:peux |vais )?(?:y )?aller a ta place\b|"
                r"\bpren\w* (?:le|ton|ta) (?:relais|creneau|seance)\b|\bremplac(?:er|e|erai)\b|"
                r"\breprendre l'organisation\b|\bprendre en charge (?:l'|le |la |les |ton |ta |tes )\w+|"
                r"\bje (?:peux |vais |pourrais )?(?:m'occuper|gerer) (?:de )?(?:l'|la |le |du |des |ton |ta |tes )\w+"),
     re.compile(r"\bremplac\w*|\ba (?:ma|ta|sa) place\b|\bquelqu'un pour\b|\bprendre le relais\b|"
                r"\bt'occup\w*|\bgere[rsz]?\b|\bprendre en charge\b")),
    ("venir ou passer chez quelqu'un",
     re.compile(r"\bje (?:viens|passe|viendrai|passerai)\b|\bje (?:peux|vais|pourrais) (?:venir|passer)\b|"
                r"\bpasser (?:te |vous )?voir\b|\bvenir (?:te |vous )?voir\b|\bje (?:te )?rejoins\b"),
     re.compile(r"\bviens\b|\bvenir\b|\bpasse[rz]?\b|\bchez (?:moi|toi|nous)\b|\brejoin\w*")),
    ("promettre",
     re.compile(r"\bje (?:te |vous )?(?:le )?promets\b|\bpromis\b|\bplus jamais\b|\bca n'arrivera plus\b|"
                r"\bje (?:te |vous )?jure\b"),
     re.compile(r"\bpromi\w*|\bpromet\w*|\bprochaine fois\b|\bplus jamais\b|\bjure\b")),
    ("appeler quelqu'un",
     re.compile(r"\bj'appelle\b|\bje (?:vais |peux |t'|l'|les |vous )+appeler\b|\bje (?:t'|l'|les )appelle\b|"
                r"\bappeler (?:ton|ta|tes|son|sa|le|la|les) \w+"),
     re.compile(r"\bappel\w*|\btelephon\w*|\bcoup de fil\b")),
    ("fixer un rendez-vous",
     re.compile(r"\bon se (?:retrouve|voit|rejoint)\b|\brendez-vous\b|\brdv\b|\bje (?:te |vous )?(?:propose|fixe) "
                r"(?:un|une) (?:creneau|date|heure)\b"),
     re.compile(r"\bretrouv\w*|\bon se voit\b|\brendez\b|\brdv\b|\bdispo\w*|\bcreneau\b|\bquand\b|\bdate\b")),
]

# Initiative suggérée par une INTERPRÉTATION (lecture commune, analyse).
INITIATIVES_LECTURE: list[tuple[re.Pattern, re.Pattern]] = [
    (re.compile(r"\balternativ\w*|\bremplac\w*|\b(?:sa|ta) place\b|\brelais\b"),
     re.compile(r"\bremplac\w*|\ba (?:ma|ta|sa) place\b|\bautre chose\b|\bplutot\b|\bquelqu'un pour\b")),
    (re.compile(r"\bvenir\b|\bpasser (?:le |la )?voir\b|\brendre visite\b|\bse deplacer\b"),
     re.compile(r"\bviens\b|\bvenir\b|\bpasse[rz]?\b|\bchez (?:moi|toi|nous)\b")),
    (re.compile(r"\bpromet\w*|\bpromesse\w*|\bs'engager\b"),
     re.compile(r"\bpromi\w*|\bpromet\w*|\bprochaine fois\b")),
    (re.compile(r"\bappeler\b|\btelephoner\b"), re.compile(r"\bappel\w*|\btelephon\w*")),
    (re.compile(r"\brendez-vous\b|\bse retrouver\b|\bfixer (?:une|un) (?:date|heure|creneau)\b|\bproposer une date\b"),
     re.compile(r"\bretrouv\w*|\brendez\b|\brdv\b|\bdispo\w*|\bquand\b|\bdate\b|\breport\w*|\bdecal\w*")),
]
_DECISION = re.compile(r"\b(?:a|ont|avez|avons) (?:decide|accepte|confirme|valide|convenu)\b|\bc'est (?:decide|convenu|acte)\b"
                       r"|\best (?:convenu|decide|acte)\b")
_DECISION_SOURCE = re.compile(r"\bdecid\w*|\baccept\w*|\bconfirm\w*|\bvalid\w*|\bconvenu\b|\bacte\b|\bd'accord\b|"
                              r"\bok\b|\bca marche\b|\bparfait\b|\bva pour\b")
_HUMOUR = re.compile(r"\bhumou?r\w*|\bblague\w*|\btaquin\w*|\bplaisant\w*|\bleger\w*|\bsecond degre\b|\brigol\w*|"
                     r"\bdrole\w*|\bironi\w*|\bjoueu\w*|\bjoue\b")
_CATEGORIQUE = re.compile(r"\b(?:clairement|forcement|evidemment|certainement|assurement|sans aucun doute|"
                          r"a coup sur|indeniablement)\b")
_CATEGORIQUE_ORIGINAL = re.compile(r"\b(?:clairement|forcément|évidemment|certainement|assurément|sans aucun doute|"
                                   r"à coup sûr|indéniablement)\b", re.I)
_NOMBRE = re.compile(r"\b\d{1,2}(?:\s?[:h]\s?\d{0,2})?\b")
_JOURS = re.compile(r"\b(?:lundi|mardi|mercredi|jeudi|vendredi|samedi|dimanche)\b")
_CITATION = re.compile(r"[«\"“]\s*([^»\"”]{3,})\s*[»\"”]")
_DECOUPE = re.compile(r"\s*(?:;|\.(?=\s|$)|,\s*(?:et|puis|mais|ou)\b|\bet (?=(?:proposer|offrir|lui|s'|il faut|"
                      r"eventuellement|éventuellement)))\s*")


def _texte(m: MessageSource) -> str:
    return normaliser(texte_affiche(m))


@dataclass
class Nettoyage:
    """Résultat du contrôle d'une interprétation : texte gardé (ou None) et
    raisons des retraits (journalisées en volume, jamais le contenu)."""

    texte: str | None
    retraits: list[str] = field(default_factory=list)
    nuances: int = 0


def nettoyer_interpretation(texte: str | None, ctx: ContexteJoint, *, question: str = "",
                            cible: MessageSource | None = None, grave: bool = False) -> Nettoyage:
    """Garde de [texte] ce que les messages récents permettent d'affirmer ou
    de supposer ; retire le reste (voir le docstring du module)."""
    if not texte or not texte.strip():
        return Nettoyage(None)
    recents = [m for m in ctx.messages if m.auteur is not None][-MESSAGES_LECTURE:]
    if cible is not None and cible not in recents:
        recents.append(cible)
    sources = " ".join(_texte(m) for m in recents) + " " + normaliser(question)
    tous = " ".join(_texte(m) for m in ctx.messages[-MESSAGES_SOURCES * 3:])
    presents = {normaliser(a) for m in recents for a in [m.auteur] if a}
    noms = {normaliser(a) for a in [ctx.contact, *ctx.participants, *(m.auteur for m in ctx.messages if m.auteur)] if a}
    garde: list[str] = []
    resultat = Nettoyage(None)
    for morceau in _DECOUPE.split(texte):
        morceau = morceau.strip(" ,;.")
        if not morceau:
            continue
        n = normaliser(morceau)
        raison = None
        for motif, justification in INITIATIVES_LECTURE:
            if motif.search(n) and not justification.search(sources):
                raison = "initiative non justifiée"
                break
        if raison is None and grave and _HUMOUR.search(n) and not re.search(r"\b(?:pas|aucun\w*|sans|eviter)\b", n):
            raison = "humour dans une situation grave"
        if raison is None and _DECISION.search(n) and not _DECISION_SOURCE.search(sources):
            raison = "décision non écrite"
        if raison is None:
            for c in _CITATION.findall(morceau):
                if normaliser(c).strip(" .!?…") not in tous:
                    raison = "citation introuvable"
                    break
        if raison is None:
            for x in _NOMBRE.findall(n) + _JOURS.findall(n):
                if x.replace(" ", "") not in sources.replace(" ", ""):
                    raison = "date ou heure absente des messages"
                    break
        if raison is None:
            for nom in noms:
                prenom = nom.split()[0] if nom.split() else nom
                if len(prenom) >= 3 and re.search(rf"\b{re.escape(prenom)}\b", n) and \
                        not any(p.startswith(prenom) for p in presents) and prenom not in sources:
                    raison = "participant absent de l'échange"
                    break
        if raison is not None:
            resultat.retraits.append(raison)
            continue
        if _CATEGORIQUE.search(n):
            morceau = _CATEGORIQUE_ORIGINAL.sub("probablement", morceau)
            resultat.nuances += 1
        garde.append(morceau)
    resultat.texte = "; ".join(garde) if garde else None
    return resultat


# --- Après la génération --------------------------------------------------------

@dataclass
class Controle:
    """Sources confrontées aux propositions d'un ensemble (non stocké :
    reconstruit à chaque complétion, « Reprendre » compris)."""

    sources: str                     # 30 derniers messages + demande, normalisés (dates, jours)
    recents: str = ""                # 8 derniers messages + demande (justification d'un engagement)
    grave: bool = False
    refus: dict[str, int] = field(default_factory=dict)    # raison → nombre (journal)

    @classmethod
    def depuis(cls, ctx: ContexteJoint, question: str = "", grave: bool = False, envoyees: str = "") -> "Controle":
        """[envoyees] : réponses déclarées envoyées (mémoire) — une promesse
        déjà faite par l'utilisateur justifie de la reformuler."""
        humains = [m for m in ctx.messages if m.auteur is not None]
        q = " " + normaliser(question) + " " + normaliser(envoyees)
        return cls(sources=" ".join(_texte(m) for m in humains[-MESSAGES_SOURCES:]) + q,
                   recents=" ".join(_texte(m) for m in humains[-MESSAGES_ENGAGEMENT:]) + q, grave=grave)

    def examiner(self, texte: str) -> str | None:
        """Raison du refus d'une proposition, ou None si elle est acceptable."""
        n = normaliser(texte)
        for nom, motif, justification in ENGAGEMENTS:
            if motif.search(n) and not justification.search(self.recents or self.sources):
                return self._refus(f"engagement non justifié ({nom})")
        compacte = self.sources.replace(" ", "")
        for x in _NOMBRE.findall(n):
            if x.replace(" ", "") not in compacte:
                return self._refus("date ou heure inventée")
        for j in _JOURS.findall(n):
            if j not in self.sources:
                return self._refus("jour inventé")
        if self.grave and _RIRES.search(texte):
            return self._refus("plaisanterie dans une situation grave")
        return None

    def _refus(self, raison: str) -> str:
        self.refus[raison] = self.refus.get(raison, 0) + 1
        return raison
