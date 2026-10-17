"""Références vérifiées : du repère proposé par le modèle au message réel.

1. Le modèle reçoit des messages numérotés pour CETTE requête ([12]) ; pour
   appuyer une phrase sur un message, il écrit [[12]] après la phrase.
2. [FiltreReperes] retire ces repères du texte diffusé (SSE) au fil de
   l'eau : jamais un identifiant technique dans les phrases visibles, même
   coupé entre deux fragments. Il note leur position dans le texte visible.
3. [verifier] contrôle chaque repère, une fois la réponse complète :
   - le numéro doit désigner un message RÉELLEMENT fourni à cette requête
     (sinon : refusé — le modèle ne peut ni inventer un identifiant, ni
     viser un message d'un autre compte : la table de correspondance est
     construite par le serveur à partir des contextes du compte du JWT) ;
   - si la phrase cite un texte entre guillemets, il doit se trouver dans
     ce message (sinon : citation incohérente, refusée) ;
   - si la phrase attribue le message à UNE personne identifiable (son
     nom, ou « tu / toi / ton » pour l'utilisateur) et que l'auteur
     enregistré est quelqu'un d'autre : attribution incorrecte, refusée.
   Une citation entre guillemets sans repère est recherchée parmi les
   messages fournis : trouvée sans ambiguïté (et sans contradiction
   d'auteur), elle devient une référence vérifiée.
4. Les références acceptées portent les données de Supabase (auteur, date,
   texte), jamais celles écrites par le modèle.

Limites : la vérification d'auteur ne comprend que les phrases simples (une
seule personne nommée) ; une interprétation (« elle plaisante ») n'est pas
vérifiable, seule l'existence et l'auteur des messages cités le sont.
"""

import re
import unicodedata
from dataclasses import dataclass, field

from .extraits import ContexteJoint, MessageSource, date_ligne, texte_affiche
from .reperes import normaliser

MAX_REFERENCES = 6
MAX_PAR_REPERE = 3   # un repère qui groupe tout un passage n'en garde que 3
LONGUEUR_EXTRAIT = 280

# Liste de numéros : « 12 », « 12, 14 », « 20-24 » (tous les tirets).
_NUMS = r"\d{1,4}(?:\s*(?:,|;|et|à|[-‐‑‒–—])\s*\d{1,4})*"
# Repères, du format demandé aux formes que le modèle écrit parfois :
#   [[12]] [[12, 14]] [[20‑24]] [12]
#   (message 5) (voir messages 22, 23 et 24) « …», message 15)
#   message 22 (au milieu d'une phrase : « message » est gardé)
_REPERE = re.compile(
    rf"\s?\(\s*\[\[?\s*(?P<f>{_NUMS})\s*\]\]?\s*\)"      # « ([[24]]) » : parenthèses comprises
    rf"|\s?\(\s*(?:voir\s+)?(?:le\s+|les\s+)?messages?\s*\[\[?\s*(?P<g>{_NUMS})\s*\]\]?\s*\)"   # « (message [[24]]) »
    rf"|\s?\[\[?\s*(?P<a>{_NUMS})\s*\]\]?"
    rf"|\s?\(\s*(?:voir\s+)?(?:les\s+|le\s+)?messages?\s+(?:n°\s*)?(?P<b>{_NUMS})\s*\)"
    rf"|,\s*messages?\s+(?:n°\s*)?(?P<c>{_NUMS})(?=\s*[)\s,.;:])"
    rf"|(?P<garde>messages?)\s+n°\s*(?P<d>{_NUMS})\b"
    rf"|(?P<garde2>messages?)\s+(?P<e>\d{{1,4}}(?:\s*(?:,|et|à|[-‐‑‒–—])\s*\d{{1,4}})*)(?![\d\w])",
    re.IGNORECASE,
)
_CITATION = re.compile(r"«\s*([^«»]{1,400}?)\s*»|“([^“”]{1,400}?)”|\"([^\"]{1,400}?)\"")
_FIN_PHRASE = ".!?\n"
# L'utilisateur SUJET (« tu as écrit », « toi tu… ») ; jamais un possessif
# ou un complément (« ton oubli », « elle te taquine »).
_DEUXIEME_PERSONNE = re.compile(r"(?<![a-z])(?:tu|toi)(?![a-z])")
# « : » et « ( » ne coupent pas : « Pepper répond : « mdr » », « une blague (« … » ».
# Le tiret d'incise coupe : « Après que tu aies dit « … » — elle répond « … » »
# (le « tu » de l'incise n'est pas le sujet de la suite).
_FIN_PROPOSITION = ".!?\n,;—–"
_MAX_PAR_PLAGE = 4


def _numeros(liste: str) -> list[int]:
    """« 12, 14 » → [12, 14] ; « 20-24 » → au plus 4 numéros répartis."""
    resultat: list[int] = []
    for morceau in re.split(r"\s*(?:,|;|et)\s*", liste):
        bornes = [int(n) for n in re.split(r"\s*(?:à|[-‐‑‒–—])\s*", morceau) if n.strip().isdigit()]
        if len(bornes) == 2 and 0 <= bornes[1] - bornes[0] <= 60:
            a, b = bornes
            pas = max(1, (b - a) // (_MAX_PAR_PLAGE - 1))
            plage = list(range(a, b + 1, pas))[: _MAX_PAR_PLAGE - 1]
            resultat.extend(plage + ([b] if b not in plage else []))
        else:
            resultat.extend(bornes)
    return resultat


def _fin_sure(t: str) -> int:
    """Longueur du début de [t] qui peut être diffusé : jusqu'à la dernière
    fin de phrase suivie d'un vrai début de phrase (un repère qui suit le
    point, « … ». [[3]] », reste avec sa phrase)."""
    fin = 0
    for m in re.finditer(r"[.!?…\n]+[»”\"]?\s+(?=[^\s\[(,])", t):
        # Jamais au milieu d'une citation (« Super. Génial. ») : la phrase
        # arrive entière au correcteur d'attributions.
        avant = t[: m.end()]
        if (avant.count("«") == avant.count("»") and avant.count("“") == avant.count("”")
                and avant.count('"') % 2 == 0):
            fin = m.end()
    return fin


def _nettoyer(t: str) -> tuple[str, list[tuple[list[int], int]]]:
    """Texte sans repères, et (numéros, position) de chaque repère."""
    visible: list[str] = []
    reperes: list[tuple[list[int], int]] = []
    longueur = 0
    curseur = 0
    for m in _REPERE.finditer(t):
        avant = t[curseur: m.start()]
        garde = m.group("garde") or m.group("garde2") or ""
        visible.append(avant)
        longueur += len(avant)
        numeros = _numeros(next(g for g in (m.group(k) for k in "abcdefg") if g))
        reperes.append((numeros, longueur))
        if garde:
            visible.append(garde)
            longueur += len(garde)
        curseur = m.end()
    visible.append(t[curseur:])
    return "".join(visible), reperes


@dataclass
class Repere:
    numeros: list[int]
    position: int          # dans le texte visible


class FiltreReperes:
    """Retire les repères du flux de texte et note leur position.

    Le texte est diffusé phrase par phrase (le reste attend sa fin de
    phrase) : un repère, même coupé entre deux fragments ou écrit
    « (message 12) », n'apparaît jamais. L'écriture progressive de Flutter
    garde le rythme mot à mot ; seul le premier mot attend la fin de la
    première phrase (les fragments arrivent bien plus vite qu'on ne lit).
    """

    def __init__(self, correcteur=None) -> None:
        self._tampon = ""
        self.visible = ""
        self.reperes: list[Repere] = []
        # (texte, repères) → (texte, repères) : chaque phrase contrôlée
        # AVANT d'être diffusée (attribution.CorrecteurAttributions).
        self.correcteur = correcteur

    def ajouter(self, fragment: str) -> str:
        """Texte visible à diffuser maintenant (éventuellement vide)."""
        self._tampon += fragment
        return self._vider(_fin_sure(self._tampon))

    def terminer(self) -> str:
        return self._vider(len(self._tampon))

    def _vider(self, jusqua: int) -> str:
        if jusqua <= 0:
            return ""
        segment, self._tampon = self._tampon[:jusqua], self._tampon[jusqua:]
        texte, reperes = _nettoyer(segment)
        if self.correcteur is not None and texte:
            texte, reperes = self.correcteur(texte, reperes)
        # Espaces laissés par un repère retiré (« phrase . », « ( ) »).
        base = len(self.visible)
        for numeros, position in reperes:
            self.reperes.append(Repere(numeros, base + position))
        self.visible += texte
        return texte


@dataclass
class Fourni:
    numero: int
    message: MessageSource
    contexte: ContexteJoint


@dataclass
class Verification:
    references: list[dict] = field(default_factory=list)
    refusees: int = 0
    attributions_contredites: int = 0
    citations_introuvables: int = 0
    # Phrases corrigées / écartées AVANT diffusion (attribution.py).
    corrigees: int = 0
    ecartees: int = 0

    @property
    def note(self) -> str | None:
        notes = []
        if self.corrigees:
            notes.append(
                "J’ai rectifié qui a écrit un message, d’après les messages "
                "enregistrés."
            )
        if self.ecartees:
            notes.append(
                "J’ai retiré une affirmation dont l’auteur ne correspondait pas "
                "aux messages enregistrés."
            )
        if self.attributions_contredites:
            notes.append(
                "Attention : d’après les messages enregistrés, une phrase de cette "
                "réponse attribue un message à la mauvaise personne. Fiez-vous aux "
                "références affichées."
            )
        if self.refusees:
            notes.append(
                "Certaines références proposées n’ont pas pu être vérifiées dans "
                "les messages enregistrés : elles ne sont pas affichées."
            )
        if self.citations_introuvables:
            notes.append(
                "Une citation de cette réponse n’a pas été retrouvée mot pour mot "
                "dans les messages fournis : prenez-la comme une reformulation."
            )
        return " ".join(notes) or None


def _simplifier(texte: str) -> str:
    t = unicodedata.normalize("NFKD", texte.lower())
    t = "".join(c for c in t if not unicodedata.combining(c))
    t = re.sub(r"[^\w\s]", " ", t)
    return " ".join(t.split())


def _phrase(texte: str, position: int) -> str:
    """Phrase qui précède un repère (le repère suit souvent le point). La
    ponctuation à l'intérieur d'une citation (« Super. Génial. ») ne coupe
    pas la phrase."""
    citations = [(m.start(), m.end()) for m in _CITATION.finditer(texte)]

    def cite(i: int) -> bool:
        return any(a <= i < b for a, b in citations)

    q = position
    while q > 0 and texte[q - 1] in " \t.!?…»\"”)":
        q -= 1
    i = q - 1
    while i >= 0 and (texte[i] not in _FIN_PHRASE or cite(i)):
        i -= 1
    return texte[i + 1: position]


def _proposition(texte: str, position: int) -> str:
    """Proposition qui précède [position] : depuis la dernière ponctuation
    (hors citations). « Pepper commence par une blague (« … » » → « Pepper
    commence par une blague »."""
    citations = [(m.start(), m.end()) for m in _CITATION.finditer(texte)]

    def cite(i: int) -> bool:
        return any(a <= i < b for a, b in citations)

    i = position - 1
    while i >= 0 and (texte[i] not in _FIN_PROPOSITION or cite(i)):
        i -= 1
    return texte[i + 1: position]


def _citations(phrase: str) -> list[str]:
    return [next(g for g in m.groups() if g is not None) for m in _CITATION.finditer(phrase)]


def _cite(citation: str, m: MessageSource) -> bool:
    c, contenu = _simplifier(citation), _simplifier(m.contenu)
    if not c or not contenu:
        return False
    return c in contenu or (len(contenu) >= 3 and contenu in c and len(contenu) * 2 >= len(c))


def _personnes(phrase: str, ctx: ContexteJoint) -> set[str]:
    """Personnes à qui la phrase semble attribuer quelque chose (hors du
    texte cité : « Arrête de te moquer » ne désigne pas l'utilisateur)."""
    p = f" {normaliser(_CITATION.sub(' ', phrase))} "
    trouvees: set[str] = set()
    noms = {n for n in [ctx.contact, *ctx.participants] if n}
    for nom in noms:
        mots = [w for w in normaliser(nom).split() if len(w) >= 3]
        if any(re.search(rf"(?<![a-z]){re.escape(w)}(?![a-z])", p) for w in mots):
            trouvees.add(ctx.moi if ctx.moi and nom == ctx.moi else nom)
    if ctx.moi and _DEUXIEME_PERSONNE.search(p):
        trouvees.add(ctx.moi)
    return trouvees


def _attribution_contredite(proposition: str, f: Fourni) -> bool:
    """Vrai si la proposition attribue le message à UNE personne
    identifiable qui n'en est pas l'auteur enregistré."""
    if f.message.auteur is None:
        return False
    personnes = _personnes(proposition, f.contexte)
    return len(personnes) == 1 and f.message.auteur not in personnes


def charge(f: Fourni, rang: int, position: int) -> dict:
    """Référence telle qu'exposée à Flutter : données de Supabase."""
    m, ctx = f.message, f.contexte
    texte = texte_affiche(m)
    return {
        "rang": rang,
        "position": position,
        "context_id": m.context_id,
        "context_message_id": m.id,
        "message_order": m.ordre,
        "author": m.auteur,
        "is_me": ctx.est_moi(m.auteur),
        "excerpt": texte if len(texte) <= LONGUEUR_EXTRAIT else texte[:LONGUEUR_EXTRAIT].rstrip() + "…",
        "kind": m.type,
        "sent_at": m.date.isoformat() if m.date else None,
        "sent_at_raw": m.date_brute,
        "date_label": date_ligne(m, ctx),
        "dates_uncertain": ctx.dates_incertaines,
        "contact_name": ctx.contact,
        "current_user_name": ctx.moi,
        # Phase 5 : message collé par l'utilisateur (non vérifié sur WhatsApp).
        "origin": m.origine,
    }


def entree_stockee(ref: dict) -> dict:
    """Ce qui est enregistré avec la réponse (messages.attachments) : les
    identifiants seulement ; le reste est relu dans Supabase à l'affichage."""
    return {
        "type": "reference_whatsapp",
        "context_id": ref["context_id"],
        "context_message_id": ref["context_message_id"],
        "message_order": ref["message_order"],
        "rang": ref["rang"],
        "position": ref["position"],
    }


def verifier(texte: str, reperes: list[Repere], fournis: dict[int, Fourni],
             propres: list[str] = ()) -> Verification:
    """[propres] : textes de JARVIS lui-même (propositions de réponse) ;
    les citer n'est ni une citation WhatsApp, ni une citation introuvable."""
    v = Verification()
    siens = [_simplifier(t) for t in propres if t.strip()]

    def propre(m) -> bool:
        c = _simplifier(next(g for g in m.groups() if g is not None))
        return bool(c) and any(c in t for t in siens)

    vus: set[str] = set()
    avec_repere: set[int] = set()   # début des phrases déjà appuyées sur un repère

    def accepter(f: Fourni, position: int) -> bool:
        cle = f"{f.message.context_id}:{f.message.ordre}"
        if cle in vus or len(v.references) >= MAX_REFERENCES:
            return False
        vus.add(cle)
        v.references.append(charge(f, len(v.references), position))
        return True

    for r in reperes:
        phrase = _phrase(texte, r.position)
        debut = r.position - len(phrase)
        avec_repere.add(debut)
        citations = [m for m in _CITATION.finditer(texte)
                     if debut <= m.start() < r.position and not propre(m)]
        valides = [fournis[n] for n in r.numeros if n in fournis]
        v.refusees += len(r.numeros) - len(valides)    # numéro inventé
        cites_par = {
            id(f): [m for m in citations if _cite(next(g for g in m.groups() if g is not None), f.message)]
            for f in valides
        }
        une_citee = any(cites_par.values())
        if citations and valides and not une_citee:
            v.refusees += 1     # citation sans rapport avec les messages visés
        acceptees = 0
        for f in valides:
            cites = cites_par[id(f)]
            if citations and not cites:
                # Repère qui groupe un passage autour d'une citation : les
                # autres messages ne sont pas des erreurs, juste écartés.
                # Aucun ne correspond à la citation : incohérent.
                continue
            if acceptees >= MAX_PAR_REPERE:
                continue
            # Qui la réponse désigne-t-elle comme auteur ? Le sujet de la
            # proposition qui précède la citation (ou le repère). Un repère
            # qui groupe plusieurs messages n'attribue rien à un seul.
            if cites:
                proposition = _proposition(texte, cites[0].start())
            elif len(r.numeros) == 1:
                proposition = _proposition(texte, r.position)
            else:
                proposition = ""
            if _attribution_contredite(proposition, f):
                v.attributions_contredites += 1
                continue
            if accepter(f, r.position):
                acceptees += 1

    # Citations sans repère : rattachées seulement si c'est sans ambiguïté.
    for m in _CITATION.finditer(texte):
        if propre(m):
            continue
        citation = next(g for g in m.groups() if g is not None)
        fin = m.end()
        phrase = _phrase(texte, fin)
        if fin - len(phrase) in avec_repere:
            continue
        tous = [f for f in fournis.values() if _cite(citation, f.message)]
        proposition = _proposition(texte, m.start())
        coherents = [f for f in tous if not _attribution_contredite(proposition, f)]
        if len(coherents) == 1:
            accepter(coherents[0], fin)
        elif tous and not coherents:
            v.attributions_contredites += 1
        elif not tous and len(_simplifier(citation).split()) >= 3:
            v.citations_introuvables += 1
    v.references.sort(key=lambda ref: ref["position"])
    for i, ref in enumerate(v.references):
        ref["rang"] = i
    return v
