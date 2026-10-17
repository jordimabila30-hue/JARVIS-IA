"""Aide à répondre et à relancer (phase 3).

Le modèle comprend lui-même la demande, quelle que soit sa formulation
(« aide-moi à lui répondre », « je veux reprendre avec humour »…). Quand
il propose des messages, il écrit une phrase d'introduction, puis un bloc
balisé, jamais affiché tel quel :

  <propositions mode="reponse">
  # Naturel
  1. [rebondir sur la blague] Texte du message à envoyer [[12]]
  2. [changer de sujet] …
  3. [poser une question] …
  # Taquin
  …
  </propositions>

  - [FiltrePropositions] sépare le bloc du texte diffusé (SSE), même coupé
    entre deux fragments ;
  - [analyser] le valide : chaque ton garde EXACTEMENT trois propositions
    distinctes (un ton incomplet ou répétitif est écarté), les repères
    [[n]] deviennent des appuis vérifiés (messages réellement fournis) ;
  - le résultat part dans l'événement `propositions` et est enregistré
    avec la réponse (`messages.attachments`, type `propositions_reponse`) :
    tous les tons d'un coup, donc changer de ton ne rappelle jamais l'IA ;
  - [bloc_precedentes] les redonne au modèle pour « pourquoi tu me proposes
    la deuxième ? » (numérotation de la requête en cours).

Rien n'est envoyé à WhatsApp : l'utilisateur copie lui-même un texte.
"""

import re
import unicodedata
from dataclasses import dataclass
from uuid import NAMESPACE_URL, uuid4, uuid5

from .references import Fourni

_NOMS_LONGUEUR = {"court": "Court", "moyen": "Moyen", "long": "Long"}

TYPE = "propositions_reponse"
PAR_TON = 3
MAX_TONS = 5
LONGUEUR_MAX = 600       # caractères d'une proposition
LONGUEUR_NOM = 24
SIMILARITE_MAX = 0.75    # au-delà : deux propositions trop proches

_OUVRE = "<propositions"
_FERME = "</propositions>"
_MODE = re.compile(r"mode\s*=\s*[\"']?(\w+)", re.I)
_TON = re.compile(r"^\s*(?:#{1,4}\s*|\*\*\s*|ton\s*:\s*)(?:ton\s*:?\s*)?[«\"“]?\s*([^*\n»\"”]{1,40}?)\s*[»\"”]?\s*\**\s*:?\s*$", re.I)
_ITEM = re.compile(r"^\s*(?:[-*•]\s+)?(?:(\d)\s*[.)\-–:]\s*|[-*•]\s+)(.+)$")
_TON_CROCHETS = re.compile(r"^\s*\[([^\]\d]{2,30})\]\s*(?:(\d)\s*[.)\-–:]\s*)?(.+)$")
# Titre de ton écrit sans « # » (« Naturel : », « Taquin ») : ligne courte,
# sans chiffre ni ponctuation de phrase (vu avec le vrai modèle).
_TON_SIMPLE = re.compile(r"^\s*[*_]*\s*(?:ton\s*:?\s*)?([A-Za-zÀ-ÿ'’ -]{2,30}?)\s*[*_]*\s*:?\s*$", re.I)


def forme(bloc: str, lignes: int = 12) -> str:
    """Forme d'un bloc illisible, SANS son contenu (journal) : lettres → a,
    chiffres gardés, ponctuation gardée."""
    sortie = []
    for l in (bloc or "").splitlines()[:lignes]:
        sortie.append(re.sub(r"[^\W\d_]+", "a", l)[:40])
    return " | ".join(sortie)
_APPROCHE = re.compile(r"^\[([^\]\d][^\]]{0,60})\]\s*|^\(([^)\d][^)]{0,60})\)\s*")
_APPUI = re.compile(r"\s*\[\[?\s*(\d{1,4}(?:\s*[,;]\s*\d{1,4})*)\s*\]\]?")


class FiltrePropositions:
    """Retire le bloc <propositions> du flux de texte (au fil de l'eau)."""

    def __init__(self) -> None:
        self._tampon = ""
        self.bloc: str | None = None      # contenu brut du bloc (ouverture comprise)
        self._dans = False
        self.ferme = False
        self._apres = False

    def ajouter(self, fragment: str) -> str:
        if self._dans:
            self.bloc += fragment
            return self._fermer()
        if self._apres:
            # Juste après le bloc : sauts de ligne et ``` de fermeture ignorés.
            fragment = fragment.lstrip("`\n ")
            if not fragment:
                return ""
            self._apres = False
            fragment = "\n\n" + fragment
        self._tampon += fragment
        i = self._tampon.lower().find(_OUVRE)
        if i >= 0 and self.bloc is None:
            visible, self.bloc = self._tampon[:i], self._tampon[i:]
            self._tampon = ""
            self._dans = True
            # Sauts de ligne avant le bloc : jamais diffusés.
            return _sans_cloture(visible).rstrip() + self._fermer()
        # Début possible de la balise en fin de tampon : retenu.
        j = self._tampon.rfind("<")
        if j >= 0 and self.bloc is None and _OUVRE.startswith(self._tampon[j:].lower()[: len(_OUVRE)]):
            visible, self._tampon = self._tampon[:j], self._tampon[j:]
            return self._retenir_espaces(visible)
        visible, self._tampon = self._tampon, ""
        return self._retenir_espaces(visible)

    def _retenir_espaces(self, visible: str) -> str:
        """Les espaces de fin attendent la suite : si c'est le bloc, ils ne
        sont jamais diffusés."""
        coeur = visible.rstrip()
        self._tampon = visible[len(coeur):] + self._tampon
        return coeur

    def _fermer(self) -> str:
        k = self.bloc.lower().find(_FERME)
        if k < 0:
            return ""
        apres = self.bloc[k + len(_FERME):]
        self.bloc = self.bloc[:k]
        self._dans = False
        self.ferme = True
        apres = apres.lstrip("`\n ")
        self._apres = not apres
        return "\n\n" + _sans_cloture(apres) if apres else ""

    def terminer(self) -> str:
        reste, self._tampon = self._tampon, ""
        return reste.rstrip()


def _sans_cloture(t: str) -> str:
    """Le modèle entoure parfois le bloc de ``` : jamais affiché."""
    return re.sub(r"`{3}[a-z]*\s*$", "", t)


def _simple(t: str) -> list[str]:
    t = unicodedata.normalize("NFKD", t.lower())
    t = "".join(c for c in t if not unicodedata.combining(c))
    return re.findall(r"\w+", t)


def trop_proches(a: str, b: str) -> bool:
    x, y = set(_simple(a)), set(_simple(b))
    if not x or not y:
        return True
    return len(x & y) / len(x | y) >= SIMILARITE_MAX


def _nettoyer(texte: str) -> str:
    texte = texte.strip().strip("*").strip()
    # Guillemets qui entourent TOUTE la proposition (pas ceux du message).
    for a, b in (("«", "»"), ('"', '"'), ("“", "”")):
        if len(texte) > 2 and texte.startswith(a) and texte.endswith(b):
            dedans = texte[1:-1]
            # « J'ai une alerte « pepper » » : seuls les guillemets extérieurs.
            if (dedans.count(a) == dedans.count(b)) if a != b else dedans.count(a) % 2 == 0:
                texte = dedans.strip()
    return texte


@dataclass
class _Ton:
    nom: str
    lignes: list[tuple[int, str, str | None]]   # (numéro, texte, longueur)


LONGUEURS = ("court", "moyen", "long")
_LONGUEUR = re.compile(
    r"^\s*[#*_\-•]*\s*(?:longueur\s*:?\s*)?(courte?s?|moyenn?e?s?|longu?e?s?)\s*[*_]*\s*(?:\([^)]*\))?\s*:?\s*$",
    re.I)
# « [Amical · Court] 1. … », « [Amical] [Court] 1. … », « [Amical/Court] … »
_TON_LONGUEUR_CROCHETS = re.compile(
    r"^\s*\[([^\]\d]{2,30}?)\s*(?:[·/|,\-–]\s*|\]\s*\[)(courte?|moyenn?e?|longu?e?)\]\s*(?:(\d)\s*[.)\-–:]\s*)?(.+)$",
    re.I)


def _longueur(mot: str | None) -> str | None:
    if not mot:
        return None
    m = mot.lower()
    return "court" if m.startswith("cour") else "moyen" if m.startswith("moy") else "long"


def lire(bloc: str | None, fournis: dict[int, Fourni]) -> tuple[str, list[tuple[str, dict, bool]], bool] | None:
    """Lecture tolérante d'un bloc <propositions> : (mode, [(ton, {longueur:
    propositions}, a_des_lignes)], longueurs_vues). Aucune règle de
    complétude ici : [analyser] (ancien chemin, un seul bloc) et la
    génération par lots (generation.py) décident."""
    if not bloc:
        return None
    entete, _, corps = bloc.partition(">")
    corps = re.split(r"</\s*propositions", corps, flags=re.I)[0]
    m = _MODE.search(entete)
    mode = "relance" if m and m.group(1).lower().startswith("relan") else "reponse"
    tons: list[_Ton] = []
    crochets = False    # forme « [Naturel] 1. message » (vue avec le vrai modèle)
    longueur: str | None = None
    vu_longueur = False

    def ton_nomme(nom: str) -> _Ton:
        ton = next((t for t in tons if t.nom.lower() == nom.lower()), None)
        if ton is None:
            ton = _Ton(nom, [])
            tons.append(ton)
        return ton

    for ligne in corps.splitlines():
        if not ligne.strip():
            continue
        tl = _TON_LONGUEUR_CROCHETS.match(ligne)
        if tl:
            vu_longueur = True
            ton_nomme(tl.group(1).strip()).lignes.append(
                (int(tl.group(3) or 0), tl.group(4), _longueur(tl.group(2))))
            continue
        lg = _LONGUEUR.match(ligne)
        if lg and tons:
            longueur = _longueur(lg.group(1))
            vu_longueur = True
            continue
        if not tons or crochets:
            c = _TON_CROCHETS.match(ligne)
            if c:
                ton_nomme(c.group(1).strip()).lignes.append((int(c.group(2) or 0), c.group(3), longueur))
                crochets = True
                continue
        item = _ITEM.match(ligne)
        if item and tons:
            tons[-1].lignes.append((int(item.group(1) or 0), item.group(2), longueur))
            continue
        titre = _TON.match(ligne) or (
            None if item else _TON_SIMPLE.match(ligne) if len(ligne.split()) <= 4 else None)
        if titre:
            tons.append(_Ton(titre.group(1).strip(" .:-"), []))
            longueur = None
        elif tons and tons[-1].lignes:
            # Suite d'une proposition sur plusieurs lignes.
            n, t, lo = tons[-1].lignes[-1]
            tons[-1].lignes[-1] = (n, f"{t} {ligne.strip()}", lo)

    lus: list[tuple[str, dict, bool]] = []
    noms: set[str] = set()
    for ton in tons:
        nom = ton.nom[:LONGUEUR_NOM].strip()
        nom = nom[:1].upper() + nom[1:]
        if not nom or nom.lower() in noms:
            continue
        groupes: dict[str | None, list[dict]] = {}
        for _, brut, lo in ton.lignes:
            approche = None
            a = _APPROCHE.match(brut.strip())
            if a:
                approche = (a.group(1) or a.group(2)).strip()
                brut = brut.strip()[a.end():]
                if _simple(approche) == _simple(nom):
                    approche = None     # « [Taquin] » sous le ton Taquin : rien appris
            appuis: list[dict] = []
            for g in _APPUI.finditer(brut):
                for n in re.split(r"\s*[,;]\s*", g.group(1)):
                    f = fournis.get(int(n))
                    if f is not None and f.message.id and len(appuis) < 3:
                        entree = {"context_id": f.message.context_id,
                                  "context_message_id": f.message.id,
                                  "message_order": f.message.ordre}
                        if entree not in appuis:
                            appuis.append(entree)
            texte = _nettoyer(_APPUI.sub("", brut))
            if not texte or len(texte) > LONGUEUR_MAX:
                continue
            groupe = groupes.setdefault(lo, [])
            if any(trop_proches(texte, p["texte"]) for p in groupe):
                continue
            if len(groupe) < PAR_TON:
                # Identifiant unique et stable (enregistré avec la proposition).
                groupe.append({"id": str(uuid4()), "texte": texte, "approche": approche,
                               "appuis": appuis, "longueur": lo, "rang": len(groupe) + 1})
        noms.add(nom.lower())
        lus.append((nom, groupes, bool(ton.lignes)))
    return mode, lus, vu_longueur


def analyser(bloc: str | None, fournis: dict[int, Fourni], contexte: str | None) -> dict | None:
    """Un bloc COMPLET à lui seul (dict prêt pour SSE et stockage) ou None :
    chaque ton porte Court / Moyen / Long × EXACTEMENT 3 propositions
    distinctes (un ton incomplet est signalé dans `incomplets`, jamais
    affiché à moitié). Ancien format (sans longueur) : accepté à la
    relecture. Les nouvelles réponses passent par generation.py, qui
    complète ce qui manque."""
    lu = lire(bloc, fournis)
    if lu is None:
        return None
    mode, lus, vu_longueur = lu
    valides: list[dict] = []
    incomplets: list[str] = []
    for nom, groupes, a_lignes in lus:
        if vu_longueur:
            if any(len(groupes.get(lo, [])) != PAR_TON for lo in LONGUEURS):
                if a_lignes:
                    incomplets.append(nom)
                continue
            propositions = [p for lo in LONGUEURS for p in groupes[lo]]
        else:
            propositions = groupes.get(None, [])
            if len(propositions) < PAR_TON:
                continue
        valides.append({"nom": nom, "propositions": propositions})
        if len(valides) >= MAX_TONS:
            break
    if not valides:
        return None
    resultat = {"mode": mode, "context_id": contexte, "tons": valides,
                "longueurs": list(LONGUEURS) if vu_longueur else []}
    if incomplets:
        resultat["incomplets"] = incomplets
    return resultat


# --- Stockage et relecture --------------------------------------------------

def entree_stockee(p: dict) -> dict:
    return {"type": TYPE, **p}


def identifiant_ancien(message_id: str | None, ton: int, rang: int) -> str:
    """Propositions enregistrées avant les identifiants : identifiant
    déterministe (même valeur sur tous les appareils, à chaque lecture)."""
    return str(uuid5(NAMESPACE_URL, f"jarvis:proposition:{message_id}:{ton}:{rang}"))


def lues(attachments, message_id: str | None = None) -> dict | None:
    """Propositions enregistrées avec une réponse, revalidées (forme), avec
    leur identifiant et leur statut « déclarée envoyée » éventuel."""
    for a in attachments or []:
        if not isinstance(a, dict) or a.get("type") != TYPE:
            continue
        mode = "relance" if a.get("mode") == "relance" else "reponse"
        if a.get("statut") == "incomplet":
            # Génération interrompue (quota, erreur) : rien d'affichable,
            # l'application propose « Reprendre » (generation.py).
            manque = 0
            for t in a.get("tons") or []:
                faits = {lo: 0 for lo in LONGUEURS}
                for x in (t.get("propositions") or []) if isinstance(t, dict) else []:
                    if isinstance(x, dict) and x.get("longueur") in faits:
                        faits[x["longueur"]] += 1
                manque += sum(max(0, PAR_TON - n) for n in faits.values())
            prevus = len(a.get("prevus") or [])
            manque += max(0, prevus - len(a.get("tons") or [])) * PAR_TON * len(LONGUEURS)
            return {"statut": "incomplet", "mode": mode, "context_id": a.get("context_id"),
                    "tons": [], "longueurs": [], "ensemble": message_id,
                    "raison": a.get("raison") or "erreur", "manquants": manque}
        envoyees = actives(attachments)
        tons = []
        for ti, t in enumerate(a.get("tons") or []):
            if not isinstance(t, dict) or not isinstance(t.get("nom"), str):
                continue
            props = [
                {"id": p["id"] if isinstance(p.get("id"), str) and p["id"] else identifiant_ancien(message_id, ti, pi),
                 "texte": p["texte"],
                 "approche": p.get("approche") if isinstance(p.get("approche"), str) else None,
                 "appuis": [x for x in (p.get("appuis") or []) if isinstance(x, dict)],
                 # Anciennes propositions (avant les longueurs) : null.
                 "longueur": p.get("longueur") if p.get("longueur") in LONGUEURS else None}
                for pi, p in enumerate(t.get("propositions") or [])
                if isinstance(p, dict) and isinstance(p.get("texte"), str) and p["texte"].strip()
            ]
            par_longueur: dict[str | None, list[dict]] = {}
            for p in props:
                e = envoyees.get(p["id"])
                p["envoyee"] = e["declared_at"] if e else None
                groupe = par_longueur.setdefault(p["longueur"], [])
                p["rang"] = len(groupe) + 1
                groupe.append(p)
            nouveau = any(lo is not None for lo in par_longueur)
            ok = bool(par_longueur) and all(len(g) == PAR_TON for g in par_longueur.values())
            if nouveau:
                ok = ok and set(par_longueur) == set(LONGUEURS)
            if ok:
                tons.append({"nom": t["nom"], "propositions": props})
        if tons:
            longueurs = [lo for lo in LONGUEURS
                         if any(p["longueur"] == lo for t in tons for p in t["propositions"])]
            return {"mode": mode, "context_id": a.get("context_id"), "tons": tons,
                    "longueurs": longueurs, "ensemble": message_id,
                    "statut": "complet",
                    "incomplets": [n for n in (a.get("incomplets") or []) if isinstance(n, str)]}
    return None


def trouver(p: dict, proposition_id: str) -> tuple[dict, dict] | None:
    """(ton, proposition) de cet identifiant, ou None."""
    for t in p["tons"]:
        for prop in t["propositions"]:
            if prop["id"] == proposition_id:
                return t, prop
    return None


# --- Réponses déclarées envoyées (phase 4) -----------------------------------
#
# {"type": "reponse_envoyee", "statut": "declaree_envoyee" | "annulee",
#  "proposition_id", "texte", "ton", "context_id", "contact", "groupe",
#  "conversation_id", "message_id", "user_id", "declared_at", "cancelled_at"}
# dans `messages.attachments` de la réponse qui porte les propositions.
# Une DÉCLARATION de l'utilisateur, jamais une livraison vérifiée par
# WhatsApp, jamais un message WhatsApp original.

TYPE_ENVOYEE = "reponse_envoyee"


def declarations(attachments) -> list[dict]:
    return [a for a in (attachments or [])
            if isinstance(a, dict) and a.get("type") == TYPE_ENVOYEE and isinstance(a.get("proposition_id"), str)]


def actives(attachments) -> dict[str, dict]:
    """proposition_id → déclaration non annulée."""
    return {d["proposition_id"]: d for d in declarations(attachments) if d.get("statut") == "declaree_envoyee"}


def appuis(p: dict) -> list[dict]:
    return [x for t in p["tons"] for prop in t["propositions"] for x in prop["appuis"]]


_RANGS = (
    (1, r"premi[eè]re|1(?:re|ere|ère)?"),
    (2, r"deuxi[eè]me|seconde|2(?:e|eme|ème|nde)?"),
    (3, r"troisi[eè]me|derni[eè]re|3(?:e|eme|ème)?"),
)


def rang_vise(question: str) -> int | None:
    """« pourquoi la deuxième ? » → 2 (None : aucune proposition désignée).
    Simple aide : le modèle reçoit le texte exact de la proposition visée
    au lieu de le retrouver (il en a mélangé deux lors d'un essai réel)."""
    q = question.lower()
    for rang, motif in _RANGS:
        if re.search(rf"(?<!\w)(?:la|le|ta|ton|proposition|réponse|reponse|n°|numéro|numero)\s*(?:{motif})(?!\w)", q):
            return rang
    return None




def longueur_affichee(p: dict, longueur: str | None) -> str | None:
    """Longueur affichée par l'application (« moyen » par défaut) ; None :
    anciennes propositions sans longueur."""
    disponibles = p.get("longueurs") or []
    if not disponibles:
        return None
    return longueur if longueur in disponibles else ("moyen" if "moyen" in disponibles else disponibles[0])


def affichees(p: dict, ton: dict, longueur: str | None) -> list[dict]:
    lo = longueur_affichee(p, longueur)
    return [x for x in ton["propositions"] if x.get("longueur") == lo]


def visee(p: dict, ton_affiche: str | None, question: str,
          longueur: str | None = None) -> tuple[dict, int, dict] | None:
    """(ton, rang, proposition) désignée par la question (« pourquoi la
    deuxième ? ») dans le ton ET la longueur AFFICHÉS (transmis par
    l'application), jamais par une position globale ni une recherche dans
    le texte."""
    rang = rang_vise(question)
    if rang is None:
        return None
    ton = next((t for t in p["tons"] if t["nom"] == ton_affiche), p["tons"][0])
    trois = affichees(p, ton, longueur)
    return ton, rang, trois[rang - 1]


def _guillemets(t: str) -> str:
    return t.replace("«", "“").replace("»", "”").replace("\n", " / ")


def bloc_precedentes(p: dict, fournis: dict[int, Fourni], ton_affiche: str | None,
                     question: str = "", longueur: str | None = None) -> str:
    """Les propositions déjà faites, pour en discuter (« pourquoi la
    deuxième ? »), avec leurs appuis renumérotés pour CETTE requête et la
    proposition visée identifiée par son identifiant, son ton et sa
    longueur. Phase 5.1 : seules les trois propositions AFFICHÉES sont
    détaillées (les autres combinaisons : tons et longueurs listés)."""
    numeros = {(f.message.context_id, f.message.ordre): n for n, f in fournis.items()}

    def appui_de(prop: dict) -> str:
        refs = [numeros.get((a.get("context_id"), a.get("message_order"))) for a in prop["appuis"]]
        refs = [str(n) for n in refs if n]
        return f" (appuis : [[{', '.join(refs)}]])" if refs else ""

    noms = [t["nom"] for t in p["tons"]]
    affiche = ton_affiche if ton_affiche in noms else noms[0]
    ton = next(t for t in p["tons"] if t["nom"] == affiche)
    lo = longueur_affichee(p, longueur)
    lignes = [
        "<propositions_precedentes>",
        f"Tu as déjà proposé des messages à l'utilisateur ({'relance' if p['mode'] == 'relance' else 'réponse'}), "
        f"tons : {', '.join(noms)}"
        + (f" ; longueurs : {', '.join(_NOMS_LONGUEUR[x] for x in p.get('longueurs') or [])}" if lo else "") + ".",
        f"Affichés à l'écran (ton « {affiche} »{f', longueur « {_NOMS_LONGUEUR[lo]} »' if lo else ''}, "
        "ce n'est pas un souhait exprimé) :",
    ]
    for prop in affichees(p, ton, longueur):
        approche = f" [{prop['approche']}]" if prop.get("approche") else ""
        envoyee = " — l'utilisateur déclare l'avoir envoyée" if prop.get("envoyee") else ""
        lignes.append(f"{prop.get('rang', '?')}.{approche} «{_guillemets(prop['texte'])}»{appui_de(prop)}{envoyee}")
    v = visee(p, ton_affiche, question, longueur)
    if v is not None:
        t, rang, prop = v
        approche = f", approche « {prop['approche']} »" if prop.get("approche") else ""
        lg = f", longueur « {_NOMS_LONGUEUR[prop['longueur']]} »" if prop.get("longueur") else ""
        lignes.append(
            f"PROPOSITION VISÉE (identifiant {prop['id']}) : ton « {t['nom']} »{lg}, n° {rang}{approche} : "
            f"«{_guillemets(prop['texte'])}»{appui_de(prop)}. Explique CELLE-CI ; cite-la exactement ou "
            "pas du tout ; n'en invente aucune autre."
        )
    lignes.append("</propositions_precedentes>")
    return "\n".join(lignes)


def bloc_memoire(envoyees: list[dict], contact: str) -> str:
    """Réponses que l'utilisateur DÉCLARE avoir envoyées à ce contact
    (choisies parmi les propositions de JARVIS) : continuité, pas de
    répétition, ton déjà choisi — jamais une préférence permanente."""
    lignes = [
        "<reponses_declarees_envoyees>",
        f"L'utilisateur a DÉCLARÉ avoir envoyé ces réponses à « {contact} » (choisies parmi tes "
        "propositions ; non vérifié dans WhatsApp, ce ne sont pas des messages importés) :",
    ]
    for e in envoyees:
        quand = str(e.get("declared_at") or "")[:16].replace("T", " ")
        doublon = " (aussi présente dans l'export WhatsApp : c'est le même message, ne la compte pas deux fois)" \
            if e.get("dans_export") else ""
        lignes.append(f"- {quand} UTC · ton « {e.get('ton')} » : «{_guillemets(str(e.get('texte') or ''))}»{doublon}")
    lignes.append(
        "Tiens-en compte pour la continuité : ne repropose pas le même message, pars de là. "
        "Un ton choisi une fois n'est pas une préférence permanente."
    )
    lignes.append("</reponses_declarees_envoyees>")
    return "\n".join(lignes)
