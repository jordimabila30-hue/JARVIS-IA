"""Ciblage DÉTERMINISTE du message visé par une question (« sa dernière
réponse », « le dernier message de Samuel », « ce que j'ai envoyé »…).

Vu en réel (2026-10-16) : le modèle commentait le dernier message DATÉ de
l'export au lieu du dernier ajout manuel (sans date), puis répétait sa
réponse fausse de l'historique. Le message visé est donc choisi ICI, dans
les messages enregistrés (auteur, provenance, ordre réel), avant tout appel
à l'IA :

  - dernier message de la conversation ;
  - dernier message d'un participant nommé (dans un groupe : SEULEMENT ses
    messages, même si d'autres ont parlé après) ;
  - dernier message reçu / envoyé ;
  - dernier ajout manuel ;
  - « sa dernière réponse » sans nom : le contact d'une discussion à deux,
    sinon la personne de la question précédente, sinon clarification.

Suivis naturels (« Pourquoi elle me dit ça ? », « Tu crois qu'il
plaisante ? », « Qu'est-ce que je devrais répondre ? ») : le référent actif
est le dernier message de la personne (nommée, de la question précédente,
ou le contact d'une discussion à deux) ; dans un groupe sans nom, le
message que l'utilisateur vient de coller (dernier ajout reçu), le dernier
reçu pour « que répondre ? », sinon clarification. Une question ancrée sur
un autre message (citation « … », « quand il m'a dit… ») ou qui suit une
telle question n'est pas ciblée : le modèle garde ce référent.

L'ordre réel est le rang (`message_order`) ; un ajout manuel sans date
n'est jamais devancé par un ancien message daté. Plusieurs personnes ou
contacts possibles : aucune supposition, clarification demandée.
"""

import re
from dataclasses import dataclass, field

from . import reperes
from .extraits import ContexteJoint, MessageSource

_DERNIER = re.compile(
    r"\bderni(?:er|ere|ers|eres)\b|\bvient d(?:e |')|\bce qu'(?:elle|il) (?:m'a |a |vient de )?"
    r"(?:dit|ecrit|repondu)\b|\bsa reponse\b|\bson message\b|\bsa reaction\b")
_MOI = re.compile(r"\b(?:mon|ma|mes) derni|\bj'ai (?:envoye|ecrit|repondu)\b|\bce que j'ai\b")
_ENVOYE = re.compile(r"\benvoy")
_RECU = re.compile(r"\brecu")
_AJOUT = re.compile(r"\bajout|\bcolle")
_INTERLOCUTEUR = re.compile(r"\breponse\b|\b(?:elle|il|sa|son|lui)\b")
# Suivi qui désigne le message actif sans le nommer (texte normalisé).
_DEICTIQUE = re.compile(
    r"\bpourquoi (?:elle|il) (?:me |m'|nous )?(?:dit|ecrit|repond|reagit|parle)\b"
    r"|\b(?:elle|il) (?:me |m'|nous )?(?:dit|ecrit|repond|reagit) (?:ca|cela|comme ca)\b"
    r"|\b(?:elle|il) (?:plaisante|rigole|blague|ironise|se moque|me taquine|me charrie|m'en veut|boude"
    r"|est (?:serieu\w*|fache\w*|vexe\w*|sarcastique|ironique|en colere))\b"
    r"|\bqu'est-ce qu'(?:elle|il) (?:veut dire|entend|sous-entend|insinue)\b|\b(?:elle|il) veut dire quoi\b"
    r"|\bca veut dire quoi\b|\bje (?:lui )?(?:reponds|dis|ecris) quoi\b"
    r"|\b(?:que|quoi|qu'est-ce que) (?:je )?(?:devrais|dois|peux|pourrais) (?:lui )?(?:repondre|dire|ecrire)\b")
_AIDE_DEICTIQUE = re.compile(r"\b(?:repondre|dire|ecrire|reponds|dis|ecris)\b")
# Question ancrée sur un message précis autre que le dernier.
_ANCRE = re.compile(r"[«\"“]|\bquand (?:elle|il|\w+) (?:m'a |a |m'avait |avait |me |m')?(?:dit|ecrit|repondu|envoye)\b")

GENRES = {
    "conversation": "dernier message de la conversation",
    "participant": "dernier message de {nom}",
    "recu": "dernier message reçu",
    "envoye": "dernier message envoyé par l'utilisateur",
    "ajout": "dernier message ajouté à la main",
}


@dataclass
class Cible:
    genre: str
    contexte: ContexteJoint
    message: MessageSource
    participant: str | None = None

    @property
    def description(self) -> str:
        return GENRES[self.genre].format(nom=self.participant or "")


@dataclass
class Ciblage:
    """Résultat : une cible vérifiée, ou des candidats (clarification)."""

    cible: Cible | None = None
    ambigus: list[str] = field(default_factory=list)


def suivi_deictique(question: str, precedentes: list[str] | None = None) -> bool:
    """« Pourquoi elle me dit ça ? » : suivi sur le message actif, sauf si la
    question (ou la précédente) est ancrée sur un autre message."""
    q = reperes.normaliser(question)
    if not _DEICTIQUE.search(q) or _ANCRE.search(question) or _ANCRE.search(q):
        return False
    if precedentes:
        avant = precedentes[-1]
        if _ANCRE.search(avant) or _ANCRE.search(reperes.normaliser(avant)):
            return False
    return True


def vise_un_dernier(question: str) -> bool:
    return bool(_DERNIER.search(reperes.normaliser(question)))


def _mots(nom: str) -> list[str]:
    return [m for m in reperes.normaliser(nom).replace("-", " ").split() if len(m) >= 3]


def _nommes(ctx: ContexteJoint, q: str) -> list[str]:
    """Participants (utilisateur compris) nommés dans la question."""
    texte = f" {re.sub(r'[^a-z0-9 ]', ' ', q)} "
    noms = []
    for nom in dict.fromkeys([ctx.contact, *ctx.participants, *(m.auteur for m in ctx.messages if m.auteur)]):
        if nom and any(f" {m} " in texte for m in _mots(nom)) and nom not in noms:
            noms.append(nom)
    # « Samuel » nomme « Samuel Petit », pas le nom du groupe.
    return [n for n in noms if not (ctx.groupe and n == ctx.contact and n not in ctx.participants)]


def _humains(ctx: ContexteJoint) -> list[MessageSource]:
    return [m for m in ctx.messages if m.auteur is not None and m.type != "system"]


def _dernier(contextes: list[ContexteJoint], garder) -> tuple[ContexteJoint, MessageSource] | None:
    """Dernier message satisfaisant [garder], dans l'ordre réel : le
    contexte le plus récent d'abord, puis le rang le plus élevé."""
    for ctx in reversed(contextes):
        for m in reversed(_humains(ctx)):
            if garder(ctx, m):
                return ctx, m
    return None


def _contacts(contextes: list[ContexteJoint]) -> list[str]:
    return list(dict.fromkeys(reperes.normaliser(c.contact) for c in contextes))


def cibler(question: str, contextes: list[ContexteJoint], precedentes: list[str] | None = None) -> Ciblage | None:
    """Message visé par [question] parmi les [contextes] chargés (pièces
    jointes visées), ou None si la question ne vise pas « le dernier »."""
    q = reperes.normaliser(question)
    deictique = not _DERNIER.search(q) and suivi_deictique(question, precedentes)
    if not contextes or not (_DERNIER.search(q) or deictique):
        return None
    noms = list(dict.fromkeys(n for c in contextes for n in _nommes(c, q)))
    plusieurs_contacts = len(_contacts(contextes)) > 1

    if deictique:
        genre = "participant"
    elif _AJOUT.search(q):
        genre = "ajout"
    elif _MOI.search(q) or (_ENVOYE.search(q) and not _RECU.search(q)):
        genre = "envoye"
    elif noms:
        genre = "participant"
    elif _RECU.search(q):
        genre = "recu"
    elif _INTERLOCUTEUR.search(q):
        genre = "participant"      # « sa dernière réponse » : qui ?
    else:
        genre = "conversation"

    if genre == "participant" and not noms:
        # Suivi (« Et sa dernière réponse ? ») : la personne de la question
        # précédente.
        for p in reversed((precedentes or [])[-3:]):
            pn = reperes.normaliser(p)
            noms = list(dict.fromkeys(n for c in contextes for n in _nommes(c, pn) if not c.est_moi(n)))
            if noms:
                break
        if not noms and deictique and not plusieurs_contacts and contextes[-1].groupe:
            # Groupe, personne non nommée : le message qu'il vient de coller,
            # ou, pour « que répondre ? », le dernier message reçu.
            ctx = contextes[-1]
            hs = _humains(ctx)
            if hs and hs[-1].manuel and not ctx.est_moi(hs[-1].auteur):
                return Ciblage(cible=Cible("participant", ctx, hs[-1], participant=hs[-1].auteur))
            if _AIDE_DEICTIQUE.search(q):
                recu = next((m for m in reversed(hs) if not ctx.est_moi(m.auteur)), None)
                if recu is not None:
                    return Ciblage(cible=Cible("recu", ctx, recu))
        if not noms:
            if plusieurs_contacts or any(c.groupe for c in contextes):
                auteurs = list(dict.fromkeys(m.auteur for c in contextes for m in _humains(c)
                                             if not c.est_moi(m.auteur)))
                return Ciblage(ambigus=auteurs[-6:] or [c.contact for c in contextes])
            ctx = contextes[-1]
            autres = [m for m in _humains(ctx) if not ctx.est_moi(m.auteur)]
            noms = [autres[-1].auteur] if autres else [ctx.contact]
    if genre == "participant" and len(noms) > 1:
        return Ciblage(ambigus=noms)
    if genre in ("conversation", "recu", "ajout") and plusieurs_contacts:
        return Ciblage(ambigus=[c.contact for c in contextes])

    nom = noms[0] if genre == "participant" else None
    garder = {
        "participant": lambda c, m: reperes.normaliser(m.auteur) == reperes.normaliser(nom),
        "recu": lambda c, m: not c.est_moi(m.auteur),
        "envoye": lambda c, m: c.est_moi(m.auteur),
        "ajout": lambda c, m: m.manuel,
        "conversation": lambda c, m: True,
    }[genre]
    trouve = _dernier(contextes, garder)
    if trouve is None:
        return Ciblage(ambigus=[nom] if nom else [])
    ctx, m = trouve
    return Ciblage(cible=Cible(genre, ctx, m, participant=(nom or m.auteur) if genre == "participant" else None))


def voisins(ciblage: Ciblage | None, avant: int = 3) -> dict[str, set[int]]:
    """Rangs à fournir OBLIGATOIREMENT au modèle (le message visé et ceux
    qui le précèdent), quelle que soit la limite de tokens."""
    if ciblage is None or ciblage.cible is None:
        return {}
    c = ciblage.cible
    humains = _humains(c.contexte)
    i = next((k for k, m in enumerate(humains) if m.ordre == c.message.ordre), None)
    if i is None:
        return {}
    return {c.contexte.id: {m.ordre for m in humains[max(0, i - avant): i + 1]}}


def bloc(ciblage: Ciblage | None, fournis: dict, envoyees: dict[str, list[dict]] | None = None) -> str | None:
    """Bloc placé juste avant la question : le message visé (numéro de
    CETTE requête, identifiant, auteur, provenance) et ce qui le précède
    dans l'ordre réel, réponses déclarées envoyées comprises (etat.fil) :
    « pourquoi elle me dit ça ? » relie sa réponse à la promesse envoyée."""
    from . import etat
    from .extraits import neutraliser

    if ciblage is None:
        return None
    if ciblage.cible is None:
        if not ciblage.ambigus:
            return None
        return ("<message_vise>\nLa question peut viser plusieurs personnes ou conversations : "
                + ", ".join(f"« {neutraliser(n)} »" for n in ciblage.ambigus)
                + ". N'en choisis aucune au hasard : demande en une phrase à l'utilisateur de qui il parle, "
                "sans analyser de message.\n</message_vise>")
    c = ciblage.cible
    numeros = {(f.message.context_id, f.message.ordre): n for n, f in fournis.items()}
    n = numeros.get((c.contexte.id, c.message.ordre))
    if n is None:
        return None

    def ligne(e: "etat.Evenement") -> str:
        # Contenu importé, cité comme dans le bloc de données : ni balise ni
        # guillemet ne peut sortir de la citation.
        return etat.ligne_evenement(e, c.contexte, numeros)

    suite = etat.fil(c.contexte, (envoyees or {}).get(c.contexte.id))
    i = next(k for k, e in enumerate(suite) if e.message is not None and e.message.ordre == c.message.ordre)

    def fourni(e: "etat.Evenement") -> bool:
        return e.declaration is not None or (e.message.context_id, e.message.ordre) in numeros

    # Échange en cours (même moment) d'abord, ce qui est plus ancien à part :
    # vu en réel, un pardon après un reproche collé à la main était lu à la
    # lumière d'une vieille blague de l'export, juste avant dans la liste.
    debut = etat.debut_episode(suite, i, c.contexte)
    avant = [e for e in suite[max(debut, i - 4): i] if fourni(e)]
    # Rien dans l'échange en cours (« Pas ce samedi… » collé seul) : ce qui
    # précède, présenté comme plus ancien.
    plus_tot = [e for e in suite[max(0, debut - 2): debut] if fourni(e)] if not avant else []
    apres = [e for e in suite[i + 1:] if e.declaration is not None]
    lignes = [
        "<message_vise>",
        f"La question porte sur le {c.description} (identifié par JARVIS dans les messages enregistrés : "
        "auteur, provenance et ordre réel ; un ajout manuel est plus récent que tout l'export).",
        f"MESSAGE VISÉ (identifiant {c.message.id or 'inconnu'}) : {ligne(suite[i])}",
    ]
    if avant:
        lignes.append("Échange en cours (même moment, ce qui précède directement le message visé) : "
                      + " ; ".join(ligne(e) for e in avant))
    if plus_tot:
        lignes.append("Plus tôt, à un autre moment (fin de l'export ou longue pause) : "
                      + " ; ".join(ligne(e) for e in plus_tot))
    lignes.append("Lis d'abord le message visé avec l'échange en cours ; ce qui est plus ancien (habitudes, "
                  "anciennes blagues) ne compte que si le message y renvoie clairement.")
    if any(e.declaration is not None for e in avant):
        lignes.append("Le message visé est arrivé APRÈS la réponse déclarée envoyée : il y réagit probablement.")
    if apres:
        lignes.append("Ensuite : " + " ; ".join(ligne(e) for e in apres))
    lignes.append(
        f"Réponds sur CE message et appuie-toi sur [[{n}]]. Ne le confonds avec aucun autre, même daté plus tard "
        "dans l'export. Les réponses précédentes de ce chat sur « le dernier message » ont été retirées : "
        "elles dataient d'avant les derniers ajouts.")
    lignes.append("</message_vise>")
    return "\n".join(lignes)


def retirer_anciens_derniers(historique: list[dict]) -> list[dict]:
    """Questions précédentes sur « le dernier message » et leurs réponses :
    écrites avant les derniers ajouts (ou fausses), elles ancraient le
    modèle sur un ancien message. Les faits enregistrés les remplacent."""
    garde: list[dict] = []
    sauter = False
    for m in historique:
        if m["role"] == "user":
            sauter = vise_un_dernier(m["content"])
            if sauter:
                continue
        elif sauter:
            sauter = False
            continue
        garde.append(m)
    return garde
