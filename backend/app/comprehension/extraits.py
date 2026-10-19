"""Messages WhatsApp joints : mise en forme, aperçu global, sélection.

Représentation canonique ([MessageSource]) : chaque message garde son
identifiant Supabase (`context_messages.id`), son contexte, son rang, son
auteur ENREGISTRÉ, son contenu original et sa date. L'auteur n'est jamais
recalculé (ni par proximité, ni par regroupement).

Format envoyé au modèle (phase 2), une ligne par message, autonome :
  [12] 06/10/2026 09:14 · Pepper Potts : «mdr»
  - [12] : numéro de la requête (1, 2, 3…), que le modèle peut citer
    ([[12]]) ; le serveur seul sait à quel message il correspond ;
  - date ET heure sur chaque ligne (plus de date à déduire d'un en-tête) ;
  - texte entre « » : un texte qui contient « Nom : … » ou plusieurs lignes
    ne peut plus passer pour un autre auteur (guillemets et retours à la
    ligne internes neutralisés).

Budget : estimation prudente (3 caractères par token, mesuré ≈ 3,4 sur des
messages français avec émojis pour le modèle configuré). Si toute la
conversation tient, elle est fournie entière ; sinon, un aperçu calculé
sur TOUS les messages + des passages choisis selon la question, et chaque
manque est signalé (« … 340 messages non inclus … ») : jamais un extrait
présenté comme la conversation complète.
"""

import math
import re
from collections import Counter
from dataclasses import dataclass, field
from datetime import date, datetime

from .reperes import Reperes, normaliser

CARACTERES_PAR_TOKEN = 3.0
LONGUEUR_MAX_MESSAGE = 1200       # caractères d'un message dans les extraits
SILENCE_NOUVEAU_FIL = 6 * 3600     # secondes : au-delà, quelqu'un « relance »

# Indices observables de ton léger (jamais une preuve d'humour).
_RIRES = re.compile(
    r"(?<![a-z])(?:ha(?:ha)+|hi(?:hi)+|hé(?:hé)+|mdr+|ptdr+|lol+|xd+|jpp)(?![a-z])"
    r"|[\U0001F602\U0001F923\U0001F605\U0001F606\U0001F604\U0001F601\U0001F61C"
    r"\U0001F61D\U0001F609\U0001F92A\U0001F60F\U0001F643]",
    re.IGNORECASE,
)

# Balises qui délimitent les données dans les instructions : neutralisées si
# un message importé les contient (tentative d'en sortir).
_BALISES = re.compile(r"<\s*/?\s*(?:donnees_whatsapp|messages|apercu|pieces_jointes|propositions(?:_precedentes)?|reponses_declarees_envoyees|message_vise|consignes_systeme)[^>]*>", re.I)


def estimer_tokens(texte: str) -> int:
    return int(len(texte) / CARACTERES_PAR_TOKEN) + 1


def neutraliser(texte: str) -> str:
    return _BALISES.sub(lambda m: m.group(0).replace("<", "‹").replace(">", "›"), texte)


def citer(texte: str) -> str:
    """Texte importé prêt à être cité entre « » : balises neutralisées, sur
    une ligne, guillemets internes remplacés (un « Nom : » ou un » ne peut
    pas sortir de la citation). Le sens du message est inchangé."""
    return (neutraliser(texte).replace("\r", "").replace("\n", " / ")
            .replace("«", "“").replace("»", "”"))


@dataclass(frozen=True)
class MessageSource:
    """Un message WhatsApp original, tel qu'enregistré (fondation des
    références de la phase 2)."""

    context_id: str
    lettre: str
    id: str | None             # context_messages.id (source de vérité)
    ordre: int                 # message_order (rang dans la sélection)
    ordre_source: int | None   # rang dans l'export d'origine
    auteur: str | None         # None : événement WhatsApp
    contenu: str
    type: str                  # text, media, deleted, system
    type_media: str | None
    date: datetime | None      # heure locale de l'export, sans fuseau
    date_brute: str
    # export | manual_received | manual_sent (phase 5) : un message collé
    # par l'utilisateur n'est pas une réception vérifiée sur WhatsApp.
    origine: str = "export"
    # Enregistrement d'un ajout manuel (UTC) : ordre réel par rapport aux
    # réponses déclarées envoyées (etat.fil). Jamais une date WhatsApp.
    cree_le: datetime | None = None

    @property
    def manuel(self) -> bool:
        return self.origine != "export"

    @property
    def reference(self) -> str:
        return f"{self.lettre}{self.ordre}"


@dataclass
class ContexteJoint:
    """Une pièce jointe WhatsApp du chat (métadonnées + messages)."""

    id: str
    lettre: str
    contact: str
    groupe: bool
    moi: str | None
    participants: list[str]
    debut: datetime | None
    fin: datetime | None
    dates_incertaines: bool
    joint_le: str
    consigne_id: str | None
    nombre: int
    messages: list[MessageSource] = field(default_factory=list)

    def est_moi(self, auteur: str | None) -> bool:
        return auteur is not None and self.moi is not None and auteur == self.moi


# --- Mise en forme ----------------------------------------------------------

def date_ligne(m: MessageSource, ctx: ContexteJoint) -> str:
    """Date et heure de CE message, telles que connues (jamais inventées)."""
    if m.date is None:
        if m.manuel and not m.date_brute:
            # Vu en réel : « date inconnue » faisait passer l'ajout pour
            # plus ancien que le dernier message daté de l'export.
            return "après l'export (date inconnue)"
        return f"date illisible ({m.date_brute})" if m.date_brute else "date inconnue"
    if ctx.dates_incertaines:
        # Ordre jour / mois non établi : la date telle qu'écrite.
        return f"{m.date_brute or m.date.strftime('%d/%m/%Y %H:%M')} (ordre jour/mois incertain)"
    return m.date.strftime("%d/%m/%Y %H:%M")


def texte_affiche(m: MessageSource) -> str:
    if m.type == "media":
        texte = f"<média : {m.type_media or 'fichier'} non transmis>"
        if m.contenu.strip():
            texte += f" {m.contenu.strip()}"
        return texte
    if m.type == "deleted":
        return "<message supprimé>"
    return m.contenu.strip()


def ligne(m: MessageSource, ctx: ContexteJoint, numero: int) -> str:
    """« [12] 06/10/2026 09:14 · Pepper Potts : «mdr» »."""
    if m.auteur is None:
        qui = "(événement WhatsApp)"
    elif ctx.est_moi(m.auteur):
        qui = f"{neutraliser(m.auteur)} (utilisateur{', ajouté à la main' if m.manuel else ''})"
    else:
        qui = f"{neutraliser(m.auteur)}{' (ajouté à la main)' if m.manuel else ''}"
    texte = texte_affiche(m)
    if len(texte) > LONGUEUR_MAX_MESSAGE:
        texte = texte[:LONGUEUR_MAX_MESSAGE].rstrip() + " […message tronqué]"
    # Le texte reste entre ses guillemets, sur sa ligne.
    return f"[{numero}] {date_ligne(m, ctx)} · {qui} : «{citer(texte)}»"


def passages(
    messages: list[MessageSource], indices: list[int], ctx: ContexteJoint, premier_numero: int
) -> str:
    """Messages choisis (indices croissants), numérotés à partir de
    [premier_numero], manques signalés."""
    sortie: list[str] = []
    precedent = -1
    for k, i in enumerate(indices):
        if i > precedent + 1:
            manque = i - precedent - 1
            sortie.append(f"[… {manque} message{'s' if manque > 1 else ''} non inclus …]")
        sortie.append(ligne(messages[i], ctx, premier_numero + k))
        precedent = i
    if indices and indices[-1] < len(messages) - 1:
        manque = len(messages) - 1 - indices[-1]
        sortie.append(f"[… {manque} message{'s' if manque > 1 else ''} plus récents non inclus …]")
    return "\n".join(sortie)


# --- Aperçu global (calculé sur tous les messages) -------------------------

def apercu(ctx: ContexteJoint, aujourd_hui: date | None = None) -> str:
    """Faits comptés sur TOUTE la pièce jointe : auteurs, période, rythme,
    relances, silences, indices de ton léger. Aucune interprétation."""
    ms = ctx.messages
    if not ms:
        return "Aucun message lisible."
    lignes: list[str] = []
    humains = [m for m in ms if m.auteur is not None]
    par_auteur = Counter(m.auteur for m in humains)
    questions = Counter(m.auteur for m in humains if m.type == "text" and "?" in m.contenu)
    rires = Counter(m.auteur for m in humains if m.type == "text" and _RIRES.search(m.contenu))
    medias = Counter(m.auteur for m in humains if m.type == "media")
    supprimes = sum(1 for m in ms if m.type == "deleted")
    for auteur, n in par_auteur.most_common(12):
        etiquette = f"{auteur} [utilisateur]" if ctx.est_moi(auteur) else auteur
        lignes.append(
            f"- {etiquette} : {n} messages ({round(100 * n / max(1, len(humains)))} %), "
            f"{questions[auteur]} avec « ? », {rires[auteur]} avec rires/émojis rieurs, "
            f"{medias[auteur]} médias"
        )
    if len(par_auteur) > 12:
        lignes.append(f"- … et {len(par_auteur) - 12} autres participants")
    if supprimes:
        lignes.append(f"- {supprimes} messages supprimés")

    dates = [m for m in ms if m.date is not None]
    sans_date = len(ms) - len(dates)
    if dates and not ctx.dates_incertaines:
        jours = {m.date.date() for m in dates}
        lignes.append(
            f"- Période : du {dates[0].date.strftime('%d/%m/%Y %H:%M')} au "
            f"{dates[-1].date.strftime('%d/%m/%Y %H:%M')} (heure locale de l'export), "
            f"{len(jours)} jours avec des messages"
        )
        mois = Counter(m.date.strftime("%m/%Y") for m in dates)
        if len(mois) > 1:
            lignes.append("- Messages par mois : " + ", ".join(f"{k} : {v}" for k, v in mois.items()))
        relances: Counter = Counter()
        silences: list[tuple[float, MessageSource, MessageSource]] = []
        for a, b in zip(dates, dates[1:]):
            ecart = (b.date - a.date).total_seconds()
            if ecart >= SILENCE_NOUVEAU_FIL and b.auteur is not None:
                relances[b.auteur] += 1
            silences.append((ecart, a, b))
        if dates[0].auteur is not None:
            relances[dates[0].auteur] += 1
        if relances:
            lignes.append(
                "- Reprises de la discussion après plus de 6 h de silence (ou premier message) : "
                + ", ".join(f"{a} {n}" for a, n in relances.most_common(6))
            )
        longs = sorted(silences, key=lambda s: s[0], reverse=True)[:3]
        longs = [s for s in longs if s[0] >= 86400]
        if longs:
            lignes.append(
                "- Plus longs silences : "
                + " ; ".join(
                    f"{round(e / 86400)} j entre le {a.date.strftime('%d/%m/%Y')} et le "
                    f"{b.date.strftime('%d/%m/%Y')}" for e, a, b in longs
                )
            )
    elif ctx.dates_incertaines:
        lignes.append("- Dates : ordre jour/mois non établi dans l'export ; dates brutes seulement.")
    if sans_date:
        lignes.append(f"- {sans_date} messages sans date lisible")
    dernier = next((m for m in reversed(ms) if m.auteur is not None), None)
    if dernier is not None:
        quand = dernier.date.strftime("%d/%m/%Y %H:%M") if dernier.date and not ctx.dates_incertaines \
            else (dernier.date_brute or "date inconnue")
        etiquette = f"{dernier.auteur} [utilisateur]" if ctx.est_moi(dernier.auteur) else dernier.auteur
        if dernier.manuel:
            quand = f"ajouté à la main après l'export, {quand}"
            texte = texte_affiche(dernier)
            if len(texte) > 160:
                texte = texte[:160].rstrip() + "…"
            # Le message lui-même : « sa dernière réponse » est sans ambiguïté.
            quand += f" : «{texte}»"
        lignes.append(f"- Dernier message : de {etiquette}, {quand}")
        lignes.append("- " + situation(ctx, aujourd_hui))
    return "\n".join(lignes)


def situation(ctx: ContexteJoint, aujourd_hui: date | None = None) -> str:
    """Qui doit la suite : auteur des derniers messages (d'affilée) et temps
    écoulé quand les dates sont fiables (aide à répondre / relancer)."""
    humains = [m for m in ctx.messages if m.auteur is not None]
    if not humains:
        return "Situation : aucun message d'un participant."
    dernier = humains[-1]
    suite = 0
    for m in reversed(humains):
        if m.auteur != dernier.auteur:
            break
        suite += 1
    moi = ctx.est_moi(dernier.auteur)
    qui = "l'utilisateur" if moi else dernier.auteur
    texte = f"Situation : {qui} a écrit en dernier ({suite} message{'s' if suite > 1 else ''} d'affilée)"
    if dernier.date is not None and not ctx.dates_incertaines and aujourd_hui is not None:
        jours = (aujourd_hui - dernier.date.date()).days
        if jours >= 0:
            texte += ", " + ("aujourd'hui" if jours == 0 else "hier" if jours == 1 else f"il y a {jours} jours")
    elif dernier.date is None:
        texte += ", date du dernier message inconnue (temps écoulé inconnu)"
    else:
        texte += ", temps écoulé inconnu (dates non fiables)"
    if ctx.moi is None:
        texte += " ; utilisateur non confirmé dans cette discussion"
    elif moi:
        texte += " ; l'interlocuteur n'a pas encore répondu : une RELANCE est possible"
    else:
        texte += " ; l'utilisateur n'a pas encore répondu : une RÉPONSE est attendue de lui"
    return texte + "."


def fiche(ctx: ContexteJoint, actif: bool) -> str:
    """Une ligne de catalogue pour la pièce jointe."""
    periode = "période inconnue"
    if ctx.debut and ctx.fin:
        periode = f"du {ctx.debut.strftime('%d/%m/%Y')} au {ctx.fin.strftime('%d/%m/%Y')}"
        if ctx.dates_incertaines:
            periode += " (dates incertaines)"
    moi = ctx.moi or "non confirmé"
    autres = [p for p in ctx.participants if p != ctx.moi]
    return (
        f"Pièce jointe {ctx.lettre}{' (active)' if actif else ''} : "
        f"{'groupe' if ctx.groupe else 'discussion'} WhatsApp « {neutraliser(ctx.contact)} », "
        f"utilisateur = {neutraliser(moi)}, autres participants : "
        f"{neutraliser(', '.join(autres[:15])) or 'inconnus'}"
        f"{' …' if len(autres) > 15 else ''} ; {ctx.nombre} messages choisis, {periode} ; "
        f"jointe le {ctx.joint_le[:10]}"
    )


# --- Sélection sous budget --------------------------------------------------

@dataclass
class Selection:
    indices: list[int]
    complete: bool
    raisons: list[str]


def _cout(messages: list[MessageSource], ctx: ContexteJoint, i: int) -> int:
    return estimer_tokens(ligne(messages[i], ctx, 999)) + 1


def selectionner(
    ctx: ContexteJoint, reperes: Reperes, budget: int, forces: list[int] | None = None,
    jalons: list[int] | None = None,
) -> Selection:
    """Indices des messages à fournir, dans [budget] tokens. [forces] :
    messages cités par les réponses précédentes (« pourquoi tu dis ça ? »),
    fournis en premier avec leurs voisins."""
    ms = ctx.messages
    n = len(ms)
    if n == 0:
        return Selection([], True, [])
    couts = [_cout(ms, ctx, i) for i in range(n)]
    if sum(couts) <= budget:
        return Selection(list(range(n)), True, ["conversation entière"])

    choisis: set[int] = set()
    depense = 0
    raisons: list[str] = []

    def prendre(indices, plafond: int) -> int:
        nonlocal depense
        pris = 0
        for i in indices:
            if i in choisis or not 0 <= i < n:
                continue
            c = couts[i] + 3
            if depense + c > budget or pris + c > plafond:
                break
            choisis.add(i)
            depense += c
            pris += c
        return pris

    # 0. Messages qui fondaient les réponses précédentes, et leur contexte.
    if forces:
        voisins = []
        for i in forces:
            voisins.extend([i, i - 1, i + 1, i - 2, i + 2])
        prendre(voisins, int(budget * 0.3))
        raisons.append("messages cités dans les réponses précédentes")

    # 1. Période demandée (« mardi dernier », « le 12 octobre »).
    if reperes.periodes and not ctx.dates_incertaines:
        dans = [
            i for i, m in enumerate(ms)
            if m.date is not None and any(p.debut <= m.date.date() <= p.fin for p in reperes.periodes)
        ]
        libelles = ", ".join(p.libelle for p in reperes.periodes)
        if dans:
            prendre(dans, int(budget * 0.7))
            raisons.append(f"messages de la période demandée ({libelles})")
        else:
            raisons.append(f"aucun message daté de la période demandée ({libelles})")

    # 1 bis. Derniers changements et décisions annoncés (etat.jalons), avec
    #    le message qui les précède : « finalement le 20 juin » ne doit pas
    #    être remplacé par l'ancienne date d'un extrait.
    if jalons:
        voisins = []
        for i in reversed(jalons):
            voisins.extend([i, i - 1])
        prendre(voisins, int(budget * 0.1))
        raisons.append("derniers changements et décisions")

    # 2. Position : début, milieu, fin.
    part = 0.45 if (reperes.debut + reperes.milieu + reperes.fin) == 1 else 0.25
    if reperes.fin:
        prendre(range(n - 1, -1, -1), int(budget * part))
        raisons.append("fin de la conversation")
    if reperes.debut:
        prendre(range(n), int(budget * part))
        raisons.append("début de la conversation")
    if reperes.milieu:
        centre = n // 2
        ordre = sorted(range(n), key=lambda i: abs(i - centre))
        prendre(ordre, int(budget * part))
        raisons.append("milieu de la conversation")

    # 3. Passages qui contiennent les mots de la question (± 2 messages).
    if reperes.mots or reperes.mots_suivi:
        textes = {i: normaliser(m.contenu) for i, m in enumerate(ms) if m.type == "text"}
        # Poids d'un mot selon sa rareté dans CETTE conversation (IDF) :
        # « Svelte » (3 messages) compte bien plus que « d'accord » ou un
        # prénom (des centaines). Sans cela, sur un long historique, les
        # messages décisifs perdaient face aux plus récents (campagne de
        # tests, groupe de 4 800 messages).
        poids: dict[str, float] = {}
        for w in {*reperes.mots, *reperes.mots_suivi}:
            df = sum(1 for t in textes.values() if w in t)
            poids[w] = math.log((len(textes) + 1) / (df + 1)) + 0.1 if df else 0.0
        scores: list[tuple[float, int]] = []
        for i, t in textes.items():
            s = (sum(2 * poids[w] for w in reperes.mots if w in t)
                 + sum(poids[w] for w in reperes.mots_suivi if w in t))
            if s:
                scores.append((s, i))
        scores.sort(key=lambda x: (-x[0], -x[1]))
        voisins = []
        for _, i in scores[:25]:
            voisins.extend([i, i - 1, i + 1, i - 2, i + 2])
        if scores:
            prendre(voisins, int(budget * 0.35))
            raisons.append("passages qui contiennent les mots de la question")

    # 4. Derniers échanges (situation récente), sauf si la question vise
    #    seulement un autre moment.
    queue = 0.12 if reperes.cible_precise and not reperes.fin else 0.2
    prendre(range(n - 1, -1, -1), int(budget * queue))
    if "fin de la conversation" not in raisons:
        raisons.append("derniers échanges")

    # 5. Le reste : fenêtres réparties sur tout l'historique, pour juger
    #    d'une tendance ou d'une évolution sans généraliser sur deux
    #    messages.
    restant = budget - depense
    if restant > 60:
        segments = 8 if (reperes.general or reperes.evolution or not reperes.cible_precise) else 4
        largeur = max(1, n // segments)
        fenetre = max(4, min(14, int(restant / segments / (sum(couts) / n + 3))))
        tour = 0
        while depense < budget - 20 and tour < 6:
            avant = depense
            for s in range(segments):
                centre = s * largeur + largeur // 2 + (tour * fenetre) % max(1, largeur)
                debut = max(0, min(n - fenetre, centre - fenetre // 2))
                prendre(range(debut, debut + fenetre), budget)
            if depense == avant:
                break
            tour += 1
        raisons.append("échantillons répartis sur toute la période")

    return Selection(sorted(choisis), False, raisons)
