"""Correction des attributions, phrase par phrase, AVANT la diffusion.

Le modèle confond parfois les auteurs (« mdr » de Pepper prêté à Tony).
Les auteurs enregistrés dans Supabase font foi : chaque phrase complète
est contrôlée avant d'être envoyée à l'application (flux SSE). Une phrase
reconnue fausse n'est donc jamais affichée, même un instant.

Ce qui est vérifié : une affirmation FACTUELLE qui associe un message
(cité entre guillemets, ou visé par un repère [[n]]) à UNE personne
identifiable (son nom, ou « tu / toi » pour l'utilisateur). Une
interprétation (« elle plaisante sans doute ») n'est pas vérifiable : elle
n'est ni corrigée ni signalée.

Décision, pour une phrase contredite par les messages enregistrés :
  - auteur réel unique (preuve non ambiguë) : la phrase est REMPLACÉE par
    une phrase factuelle construite avec les données de Supabase
    (« C'est Pepper Potts qui a écrit « mdr ». »), avec son repère quand
    le message est unique. Jamais de substitution de nom dans la phrase du
    modèle (accords, pronoms : le sens pourrait rester faux) ;
  - plusieurs auteurs possibles : reformulée sans choisir
    (« « oui » apparaît dans des messages de Rhodey et de toi. ») ;
  - sinon : la phrase est écartée.
Le texte d'une citation n'est jamais modifié : c'est le message original
quand il est court, sinon la citation du modèle (déjà retrouvée dans le
message).
"""

import re
import unicodedata
from dataclasses import dataclass, field

from .references import _CITATION, Fourni, _attribution_contredite, _cite, _proposition

LONGUEUR_CITATION = 120   # au-delà, la citation du modèle (vérifiée) est gardée
_COUPURE = re.compile(r"[.!?…\n]+[»”\"]?\s+")
# La phrase parle d'une proposition de JARVIS (pas d'un message WhatsApp).
_VISE_PROPOSITION = re.compile(r"propos|suggér|sugger|option|réponse|reponse|message que je", re.I)


def _mots(t: str) -> list[str]:
    t = unicodedata.normalize("NFKD", t.lower())
    t = "".join(c for c in t if not unicodedata.combining(c))
    return re.findall(r"\w+", t)


def _jaccard(a: str, b: str) -> float:
    x, y = set(_mots(a)), set(_mots(b))
    return len(x & y) / len(x | y) if x and y else 0.0


@dataclass
class Contradiction:
    candidats: list[Fourni]      # messages qui correspondent réellement
    citation: str | None


def _equilibre(t: str) -> bool:
    return (t.count("«") == t.count("»") and t.count("“") == t.count("”")
            and t.count('"') % 2 == 0)


def phrases(texte: str) -> list[tuple[int, int]]:
    """Découpe en phrases (début, fin), espaces de fin compris ; jamais à
    l'intérieur d'une citation (« Super. Génial. »)."""
    bornes: list[tuple[int, int]] = []
    debut = 0
    for m in _COUPURE.finditer(texte):
        if _equilibre(texte[debut: m.end()]):
            bornes.append((debut, m.end()))
            debut = m.end()
    if debut < len(texte):
        bornes.append((debut, len(texte)))
    return bornes


def _texte_cite(m) -> str:
    return next(g for g in m.groups() if g is not None)


def _nom(f: Fourni) -> str:
    return "toi" if f.contexte.est_moi(f.message.auteur) else (f.message.auteur or "")


def contradictions(phrase: str, reperes: list[tuple[list[int], int]],
                   fournis: dict[int, Fourni]) -> list[Contradiction]:
    """Attributions de [phrase] contredites par les messages enregistrés.
    [reperes] : (numéros, position dans la phrase)."""
    trouvees: list[Contradiction] = []
    citations = list(_CITATION.finditer(phrase))
    for numeros, position in reperes:
        avant = [c for c in citations if c.start() < position]
        valides = [fournis[n] for n in numeros if n in fournis]
        for f in valides:
            cites = [c for c in avant if _cite(_texte_cite(c), f.message)]
            if avant and not cites:
                continue   # message groupé autour d'une autre citation
            if cites:
                proposition = _proposition(phrase, cites[0].start())
            elif len(numeros) == 1:
                proposition = _proposition(phrase, position)
            else:
                continue   # un groupe de messages n'attribue rien à un seul
            if _attribution_contredite(proposition, f):
                trouvees.append(Contradiction([f], _texte_cite(cites[0]) if cites else None))
    if reperes:
        return trouvees
    # Citations sans repère : recherchées dans tous les messages fournis.
    for c in citations:
        citation = _texte_cite(c)
        tous = [f for f in fournis.values() if _cite(citation, f.message)]
        if not tous:
            continue
        proposition = _proposition(phrase, c.start())
        if all(_attribution_contredite(proposition, f) for f in tous):
            trouvees.append(Contradiction(tous, citation))
    return trouvees


def _objet(c: Contradiction) -> str:
    """« « mdr » » : le message original s'il est court, sinon la citation."""
    if len(c.candidats) == 1:
        m = c.candidats[0].message
        contenu = " ".join(m.contenu.split())
        if m.type == "text" and contenu and len(contenu) <= LONGUEUR_CITATION:
            return f"« {contenu} »"
    if c.citation:
        return f"« {c.citation.strip()} »"
    return "ce message"


def phrase_factuelle(c: Contradiction) -> tuple[str, int | None] | None:
    """Phrase vraie d'après Supabase, et le repère à garder (ou None)."""
    noms: list[str] = []
    for f in c.candidats:
        if f.message.auteur is None:
            return None
        nom = _nom(f)
        if nom not in noms:
            noms.append(nom)
    if len(noms) == 1:
        qui = noms[0]
        verbe = "as" if qui == "toi" else "a"
        repere = c.candidats[0].numero if len(c.candidats) == 1 else None
        return f"C'est {qui} qui {verbe} écrit {_objet(c)}.", repere
    if not c.citation or len(noms) > 4:
        return None
    noms.sort(key=lambda n: n == "toi")    # « toi » en dernier
    liste = ", ".join(f"de {n}" for n in noms[:-1]) + f" et de {noms[-1]}"
    return f"{_objet(c)} apparaît dans des messages {liste}.", None


@dataclass
class CorrecteurAttributions:
    """Branché sur le filtre des repères : reçoit chaque segment visible
    (phrases complètes) et ses repères, rend le segment corrigé."""

    fournis: dict[int, Fourni]
    # Propositions déjà faites par JARVIS (phase 3) et celle que vise la
    # question (« pourquoi la deuxième ? ») : une citation qui prétend en
    # être une mais n'existe pas est rétablie mot pour mot.
    propositions: list[str] = field(default_factory=list)
    visee: str | None = None
    corrigees: int = 0
    ecartees: int = 0
    propositions_retablies: int = 0

    def _retablir(self, phrase: str, locaux: list[tuple[list[int], int]]):
        """Citation d'une proposition inexistante → texte exact (proposition
        visée, sinon la plus proche si elle est presque identique)."""
        if not self.propositions:
            return phrase, locaux
        for m in reversed(list(_CITATION.finditer(phrase))):
            cite = _texte_cite(m)
            if len(cite.split()) < 4 or any(_cite(cite, f.message) for f in self.fournis.values()):
                continue
            simple = " ".join(_mots(cite))
            if any(simple and simple in " ".join(_mots(p)) for p in self.propositions):
                continue    # proposition citée exactement (ou un extrait)
            proche = max(self.propositions, key=lambda p: _jaccard(cite, p))
            if _jaccard(cite, proche) >= 0.5:
                juste = proche
            elif self.visee and _VISE_PROPOSITION.search(phrase):
                juste = self.visee
            else:
                continue
            nouveau = f"« {juste} »"
            decalage = len(nouveau) - (m.end() - m.start())
            phrase = phrase[: m.start()] + nouveau + phrase[m.end():]
            locaux = [(n, p + decalage if p >= m.end() else p) for n, p in locaux]
            self.propositions_retablies += 1
        return phrase, locaux

    def __call__(self, texte: str, reperes: list[tuple[list[int], int]]):
        sortie: list[str] = []
        nouveaux: list[tuple[list[int], int]] = []
        longueur = 0
        bornes = phrases(texte)
        for k, (debut, fin) in enumerate(bornes):
            dernier = k == len(bornes) - 1
            locaux = [(n, p - debut) for n, p in reperes
                      if debut <= p < fin or (dernier and p == fin)]
            phrase, locaux = self._retablir(texte[debut:fin], locaux)
            fautes = contradictions(phrase, locaux, self.fournis)
            if not fautes:
                sortie.append(phrase)
                nouveaux.extend((n, longueur + p) for n, p in locaux)
                longueur += len(phrase)
                continue
            espace = phrase[len(phrase.rstrip()):]
            remplacements = [phrase_factuelle(c) for c in fautes[:2]]
            if len(fautes) > 2 or any(r is None for r in remplacements):
                self.ecartees += 1
                continue
            vus: set[str] = set()
            morceaux: list[str] = []
            for texte_r, repere in remplacements:
                if texte_r in vus:
                    continue
                vus.add(texte_r)
                if morceaux:
                    morceaux.append(" ")
                    longueur += 1
                morceaux.append(texte_r)
                longueur += len(texte_r)
                if repere is not None:
                    nouveaux.append(([repere], longueur))
            self.corrigees += 1
            suffixe = espace or ("" if dernier else " ")
            sortie.append("".join(morceaux) + suffixe)
            longueur += len(suffixe)
        return "".join(sortie), nouveaux
