"""Repères d'une question sur une conversation importée.

Analyse simple et déterministe (aucune IA) de la question de l'utilisateur,
et des questions précédentes pour les suivis (« et vers la fin ? ») :

  - période visée : « hier », « mardi dernier », « le 12 octobre »,
    « 12/10 », « en mars », « la semaine dernière » ;
  - position : début, milieu, fin (« son dernier message ») ;
  - portée : évolution (« comment ça a changé ») ou tendance générale
    (« est-ce qu'on plaisante souvent ») : il faut des exemples répartis
    dans tout l'historique ;
  - mots utiles, pour retrouver les passages qui en parlent.

Ces repères orientent la sélection des extraits ; ils ne remplacent jamais
la lecture du modèle. Une date relative se calcule depuis [aujourd_hui]
(date du serveur) : aucune heure ni aucun fuseau n'est inventé.
"""

import re
import unicodedata
from dataclasses import dataclass, field
from datetime import date, timedelta

_JOURS = ["lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche"]
_MOIS = {
    "janvier": 1, "fevrier": 2, "mars": 3, "avril": 4, "mai": 5, "juin": 6,
    "juillet": 7, "aout": 8, "septembre": 9, "octobre": 10, "novembre": 11,
    "decembre": 12,
}

_MOTS_VIDES = set("""
a ai as au aux avait avec avoir c ca ce ceci cela celle celles celui ces cet
cette chez comme comment d dans de des deja dis dit dire donc du elle elles
en encore est et etait ete etre eu fait faire il ils j je jarvis l la le les
leur leurs lui m ma mais me meme mes moi mon n ne ni nos notre nous on ou
par pas peu peut plus pour pourquoi qu quand que quel quelle quelles quels
qui quoi s sa sans se ses si son sont sur t ta te tes toi ton tous tout
toute toutes tres tu un une vers vos votre vous y oui non bien alors aussi
juste rien chose choses quelque truc trucs penses pense trouves trouve crois
explique expliquer resume resumer analyse analyser regarde dis-moi message
messages discussion conversation conversations whatsapp parle parler parlait
parlions parle-t-on avons ont etaient avez etes suis fais vais va vont
toujours souvent jamais pareil fin debut milieu dernier derniere derniers
dernieres premier premiere premiers premieres probablement vraiment
""".split())

# Motifs (expressions régulières sur le texte normalisé), bornés aux mots :
# « la fin » ne reconnaît pas « la finance ».
_DEBUT = (r"au debut", r"debut de", r"au depart", r"premiers? messages?",
          r"premiers echanges", r"commencement", r"a l'origine", r"en premier")
_FIN = (r"vers la fin", r"a la fin", r"la fin", r"derniers? messages?",
        r"derniere? message", r"derniers echanges", r"dernierement", r"recemment",
        r"en dernier", r"dernier sujet", r"derniere fois", r"ou en etait",
        r"on en etait", r"ou on en est")
# Aide à répondre / relancer (phase 3) : simple INDICE pour le budget
# (fin de la conversation, longueur de sortie). C'est le modèle qui
# comprend la demande, quelle que soit sa formulation.
# « réponse » seul ne suffit pas : « que penses-tu de sa dernière réponse ? »
# demande une analyse (vu en réel : budget d'extraits réduit à tort).
_AIDE = (r"repond\w*", r"(?:une|quelle|ma|mes|des|meilleure|bonne|autre) reponses?",
         r"reponses? (?:a|pour) (?:lui|elle|envoyer|donner)", r"aide[- ]?moi", r"m'aider",
         r"relanc\w*", r"reprendre", r"renouer",
         r"(?:que|quoi|qu'est-ce que) (?:je )?(?:pourrais|peux|devrais|dois) (?:lui )?(?:dire|ecrire|envoyer)",
         r"lui (?:dire|ecrire|envoyer|repondre)", r"propose\w*", r"suggere\w*", r"formuler",
         r"quoi (?:lui )?(?:dire|ecrire)", r"que (?:lui )?(?:dire|ecrire)", r"message a (?:lui )?envoyer")
_MILIEU = (r"au milieu", r"milieu de")
_EVOLUTION = (r"evolu\w*", r"a change", r"ont change", r"change\w*", r"compar\w*",
              r"au fil", r"avant et apres", r"different\w*", r"devenu\w*",
              r"devient", r"progress\w*",
              # Suivi : « Et avant, c'était pareil ? » (comparer à plus tôt).
              r"et avant", r"avant ca", r"(?:c'etait|c'est|etait) pareil", r"comme avant", r"d'habitude")
_GENERAL = (r"souvent", r"toujours", r"jamais", r"en general", r"habitude\w*",
            r"frequemment", r"regulierement", r"plaisant\w*", r"plaisant", r"humour\w*",
            r"blague\w*", r"taquin\w*", r"ironi\w*", r"sarcas\w*", r"second degre",
            r"ton", r"ambiance", r"relation", r"sujets", r"themes?", r"resum\w*",
            r"analys\w*", r"en penses?", r"remarque\w*", r"important\w*",
            r"globalement", r"recurrent\w*", r"reviennent")


def _contient(t: str, motifs: tuple[str, ...]) -> bool:
    return any(re.search(rf"(?<![a-z]){m}(?![a-z])", t) for m in motifs)


def normaliser(texte: str) -> str:
    """Minuscules, sans accents, apostrophes droites, espaces simples."""
    t = unicodedata.normalize("NFKD", texte.lower())
    t = "".join(c for c in t if not unicodedata.combining(c))
    t = t.replace("’", "'").replace("‘", "'")
    return " ".join(t.split())


@dataclass(frozen=True)
class Periode:
    debut: date
    fin: date          # inclusive
    libelle: str


@dataclass
class Reperes:
    periodes: list[Periode] = field(default_factory=list)
    debut: bool = False
    milieu: bool = False
    fin: bool = False
    evolution: bool = False
    general: bool = False
    mots: list[str] = field(default_factory=list)
    # Mots des questions précédentes (suivi) : poids plus faible.
    mots_suivi: list[str] = field(default_factory=list)
    # Indice d'une demande d'aide à répondre / relancer.
    aide_reponse: bool = False

    @property
    def cible_precise(self) -> bool:
        """La question vise un moment ou un passage précis."""
        return bool(self.periodes) or self.debut or self.milieu or self.fin


def _mots(t: str) -> list[str]:
    vus: list[str] = []
    for m in re.findall(r"[a-z0-9][a-z0-9'-]{2,}", t):
        m = m.split("'")[-1].strip("-")
        if len(m) < 4 or m in _MOTS_VIDES or m.isdigit() or m in _MOIS or m in _JOURS:
            continue
        if m not in vus:
            vus.append(m)
    return vus[:12]


def _periodes(t: str, aujourd_hui: date) -> list[Periode]:
    p: list[Periode] = []
    if "avant-hier" in t or "avant hier" in t:
        j = aujourd_hui - timedelta(days=2)
        p.append(Periode(j, j, "avant-hier"))
    elif re.search(r"\bhier\b", t):
        j = aujourd_hui - timedelta(days=1)
        p.append(Periode(j, j, "hier"))
    if re.search(r"\baujourd'hui\b|\bce matin\b|\bce soir\b", t):
        p.append(Periode(aujourd_hui, aujourd_hui, "aujourd'hui"))
    if "semaine derniere" in t:
        lundi = aujourd_hui - timedelta(days=aujourd_hui.weekday() + 7)
        p.append(Periode(lundi, lundi + timedelta(days=6), "la semaine dernière"))
    elif "cette semaine" in t:
        lundi = aujourd_hui - timedelta(days=aujourd_hui.weekday())
        p.append(Periode(lundi, aujourd_hui, "cette semaine"))
    if "mois dernier" in t:
        premier = aujourd_hui.replace(day=1)
        fin = premier - timedelta(days=1)
        p.append(Periode(fin.replace(day=1), fin, "le mois dernier"))
    if "week-end dernier" in t or "weekend dernier" in t:
        samedi = aujourd_hui - timedelta(days=(aujourd_hui.weekday() - 5) % 7 or 7)
        p.append(Periode(samedi, samedi + timedelta(days=1), "le week-end dernier"))
    for i, jour in enumerate(_JOURS):
        if re.search(rf"\b{jour}\b", t):
            # « mardi » ou « mardi dernier » : le plus récent avant aujourd'hui.
            ecart = (aujourd_hui.weekday() - i) % 7 or 7
            j = aujourd_hui - timedelta(days=ecart)
            p.append(Periode(j, j, f"{jour} {j.strftime('%d/%m/%Y')}"))
    # « 12/10 », « 12/10/2026 », « 12-10-26 » (jour/mois, usage français)
    for m in re.finditer(r"\b(\d{1,2})[/.-](\d{1,2})(?:[/.-](\d{2,4}))?\b", t):
        j, mo, a = int(m.group(1)), int(m.group(2)), m.group(3)
        annee = aujourd_hui.year if a is None else (int(a) + 2000 if len(a) == 2 else int(a))
        try:
            d = date(annee, mo, j)
        except ValueError:
            continue
        if a is None and d > aujourd_hui:
            d = d.replace(year=annee - 1)
        p.append(Periode(d, d, d.strftime("%d/%m/%Y")))
    # « 12 octobre », « le 3 mars 2025 », puis « en mars » (mois entier)
    noms = "|".join(_MOIS)
    dates_mois = set()
    for m in re.finditer(rf"\b(\d{{1,2}})(?:er)? ({noms})(?: (\d{{4}}))?\b", t):
        j, mo = int(m.group(1)), _MOIS[m.group(2)]
        annee = int(m.group(3)) if m.group(3) else aujourd_hui.year
        try:
            d = date(annee, mo, j)
        except ValueError:
            continue
        if not m.group(3) and d > aujourd_hui:
            d = d.replace(year=annee - 1)
        dates_mois.add(m.group(2))
        p.append(Periode(d, d, d.strftime("%d/%m/%Y")))
    for m in re.finditer(rf"\b(?:en|de|du mois de|au mois de|debut|fin) ({noms})(?: (\d{{4}}))?\b", t):
        if m.group(1) in dates_mois:
            continue
        mo = _MOIS[m.group(1)]
        annee = int(m.group(2)) if m.group(2) else aujourd_hui.year
        if not m.group(2) and date(annee, mo, 1) > aujourd_hui:
            annee -= 1
        debut = date(annee, mo, 1)
        fin = (date(annee + (mo == 12), mo % 12 + 1, 1) - timedelta(days=1))
        p.append(Periode(debut, fin, f"{m.group(1)} {annee}"))
    return p


def analyser(question: str, precedentes: list[str], aujourd_hui: date) -> Reperes:
    """Repères de [question] ; [precedentes] : questions précédentes de
    l'utilisateur dans ce chat (la plus récente en dernier)."""
    t = normaliser(question)
    r = Reperes()
    r.periodes = _periodes(t, aujourd_hui)
    r.debut = _contient(t, _DEBUT)
    r.milieu = _contient(t, _MILIEU)
    r.fin = _contient(t, _FIN)
    r.aide_reponse = _contient(t, _AIDE)
    if r.aide_reponse:
        r.fin = True    # pour répondre, il faut surtout la fin
    r.evolution = _contient(t, _EVOLUTION)
    r.general = _contient(t, _GENERAL)
    r.mots = _mots(t)
    # Suivi : « et vers la fin, c'est toujours pareil ? » reprend le sujet
    # de la question précédente (les plaisanteries).
    for q in reversed(precedentes[-2:]):
        p = normaliser(q)
        if not r.general and _contient(p, _GENERAL):
            r.general = True
        for m in _mots(p):
            if m not in r.mots and m not in r.mots_suivi:
                r.mots_suivi.append(m)
    r.mots_suivi = r.mots_suivi[:8]
    return r
