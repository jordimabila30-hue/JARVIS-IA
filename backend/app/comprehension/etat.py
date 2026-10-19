"""État de compréhension PARTAGÉ : faits calculés sur les messages
enregistrés, sans IA, reconstruits à chaque demande (rien de stocké).

Une même source pour la réponse principale et pour TOUS les lots de
propositions, afin qu'aucune partie du moteur ne comprenne la situation
autrement qu'une autre :

  - habitudes d'écriture observables par participant (longueur, émojis,
    rires, questions, tu / vous, expressions récurrentes) et leur évolution
    récente — des tendances, jamais un profil psychologique ;
  - jalons : messages qui annoncent un changement ou une décision
    (« finalement », « on décale », « mise à jour »…) ;
  - indices de sérieux dans les derniers messages (hôpital, licenciement,
    « je suis sérieuse »…) : un indice, pas une conclusion ;
  - proportion : le dernier message reçu est-il très court (« ok 👍 ») ;
  - suite récente : ajouts manuels et réponses déclarées envoyées dans
    leur ordre réel (dates d'ajout et de déclaration, jamais inventées) ;
  - message auquel répondre (lots) ;
  - inconnues (dates manquantes, utilisateur non confirmé).

L'INTERPRÉTATION (ton, intention) reste celle du modèle : la réponse
principale l'écrit une fois (attribut `lecture` du bloc de propositions),
et tous les lots la reçoivent telle quelle (generation.py).
"""

import re
from collections import Counter
from dataclasses import dataclass
from datetime import datetime
from statistics import median

from .extraits import _RIRES, ContexteJoint, MessageSource, citer, date_ligne, texte_affiche
from .reperes import normaliser

# Registre (tutoiement / vouvoiement) : partagé avec generation.py.
MOTS_TU = re.compile(r"\b(?:tu|toi|tes)\b|\bt['’]", re.I)
MOTS_VOUS = re.compile(r"\b(?:vous|votre|vos)\b", re.I)
TU_SEUL = re.compile(r"\b(?:tu|toi)\b|\bt['’]", re.I)

_EMOJI = re.compile("[\U0001F300-\U0001FAFF☀-➿]")
_MOT = re.compile(r"\w+")

# Changement ou décision annoncés (texte normalisé, sans accents).
_JALON = re.compile(
    r"\bfinalement\b|\bdecision\b|\bdecid\w*|\bon part sur\b|\bdecal\w*|\bdeplac\w*|\brepor\w*|"
    r"\bmise a jour\b|\bannul\w*|\berreur\b|\bau lieu d[ue]\b|\bon garde\b|\bacte\w*\b|\bc'est (?:decide|valide)\b")
# Indices de gravité (aucune plaisanterie) / de tension (humour seulement
# s'il est clairement bienvenu), dans les derniers messages seulement.
_GRAVE = re.compile(
    r"\bhopita\w*|\bhospitalis\w*|\bmalad\w*|\bdeces\b|\bdecede\w*|\bmort\b|\benterrement|\baccident\w*|"
    r"\burgence\w*|\blicenci\w*|\bchomage\b|\brupture\b|\bdivorc\w*|\bdeprim\w*|\bpleur\w*|\bcancer\b|"
    r"\bfunerailles\b|\bça va pas\b|\bca va pas\b|\bca ne va pas\b|\bva pas (?:trop |tres )?bien\b")
_TENSION = re.compile(
    r"\bje suis serieu\w*|\bc'est serieux\b|\bpas drole\b|\bfache\w*|\bvexe\w*|\ben colere\b|\bdecu\w*|"
    r"\bblesse\w*|\bpas une blague\b|\bj'en ai marre\b|\bmarre\b|\binquiet\w*|\bpeur\b|\btriste\w*")

DERNIERS_SERIEUX = 6
MOTS_LEGER_MAX = 4          # « ok 👍 », « d'accord merci » : message très court
MAX_JALONS = 4
MAX_FIL = 6
SILENCE_NOUVEL_ECHANGE = 6 * 3600   # secondes (comme extraits.SILENCE_NOUVEAU_FIL)

PROPORTION_NORMALE = "normale"
PROPORTION_LEGERE = "legere"


def _mots(texte: str) -> int:
    return len(_MOT.findall(texte))


def humains(ctx: ContexteJoint) -> list[MessageSource]:
    return [m for m in ctx.messages if m.auteur is not None and m.type != "system"]


# --- Habitudes ------------------------------------------------------------------

@dataclass
class Habitude:
    auteur: str
    nombre: int
    mots: int              # médiane de mots par message (texte)
    emojis: int            # % de messages avec un émoji
    rires: int             # % de messages avec un rire (mdr, haha, 😂…)
    questions: int         # % de messages avec « ? »
    registre: str          # « tutoie » | « vouvoie » | ""
    expressions: list[str]
    recent: str = ""       # évolution récente notable, sinon vide


def _profil(ms: list[MessageSource]) -> tuple[int, int, int, int]:
    textes = [m.contenu for m in ms if m.type == "text" and m.contenu.strip()]
    if not textes:
        return 0, 0, 0, 0
    n = len(textes)
    return (int(median(_mots(t) for t in textes)),
            round(100 * sum(1 for t in textes if _EMOJI.search(t)) / n),
            round(100 * sum(1 for t in textes if _RIRES.search(t)) / n),
            round(100 * sum(1 for t in textes if "?" in t) / n))


def habitudes(ctx: ContexteJoint, auteurs: list[str] | None = None, recents: int = 40,
              max_auteurs: int = 5) -> list[Habitude]:
    """Tendances d'écriture observées, par auteur (les plus actifs d'abord,
    ou [auteurs]). « recent » : seulement si les [recents] derniers
    messages s'écartent nettement de l'ensemble."""
    par: dict[str, list[MessageSource]] = {}
    for m in humains(ctx):
        par.setdefault(m.auteur, []).append(m)
    ordre = auteurs or [a for a, _ in Counter({a: len(v) for a, v in par.items()}).most_common(max_auteurs)]
    resultat = []
    for a in ordre:
        ms = par.get(a)
        if not ms:
            continue
        mots, emo, rires, q = _profil(ms)
        tu = sum(len(MOTS_TU.findall(m.contenu)) for m in ms if m.type == "text")
        vous = sum(len(MOTS_VOUS.findall(m.contenu)) for m in ms if m.type == "text")
        reg = "tutoie" if tu >= 2 and tu >= 2 * vous else "vouvoie" if vous >= 2 and vous >= 2 * tu and not ctx.groupe else ""
        # Réactions courtes récurrentes (« mdr », « ça marche », « 😅 »),
        # comptées sans casse ni accents, montrées telles qu'écrites.
        courts: Counter = Counter()
        forme: dict[str, str] = {}
        for m in ms:
            if m.type == "text" and m.contenu.strip() and _mots(m.contenu) <= 3:
                cle = normaliser(m.contenu).strip(" .!")
                if cle:
                    courts[cle] += 1
                    forme.setdefault(cle, m.contenu.strip())
        expressions = [forme[e] for e, n in courts.most_common(4) if n >= 3]
        h = Habitude(a, len(ms), mots, emo, rires, q, reg, expressions)
        if len(ms) >= 2 * recents:
            r_mots, r_emo, r_rires, _ = _profil(ms[-recents:])
            ecarts = []
            if mots and (r_mots >= 1.8 * mots or r_mots <= 0.55 * mots) and abs(r_mots - mots) >= 3:
                ecarts.append(f"messages plus {'longs' if r_mots > mots else 'courts'} (médiane {r_mots} mots)")
            if abs(r_rires - rires) >= 20:
                ecarts.append(f"{'plus' if r_rires > rires else 'moins'} de rires ({r_rires} %)")
            if abs(r_emo - emo) >= 25:
                ecarts.append(f"{'plus' if r_emo > emo else 'moins'} d'émojis ({r_emo} %)")
            h.recent = ", ".join(ecarts)
        resultat.append(h)
    return resultat


def ligne_habitude(h: Habitude, ctx: ContexteJoint) -> str:
    qui = f"{h.auteur} [utilisateur]" if ctx.est_moi(h.auteur) else h.auteur
    parts = [f"médiane {h.mots} mot{'s' if h.mots > 1 else ''}",f"émojis {h.emojis} %", f"rires {h.rires} %", f"questions {h.questions} %"]
    if h.registre:
        parts.append(h.registre)
    texte = f"{citer(qui)} ({h.nombre} messages) : " + ", ".join(parts)
    if h.expressions:
        texte += " ; revient souvent : " + ", ".join(f"«{citer(e)}»" for e in h.expressions)
    if h.recent:
        texte += f" ; récemment : {h.recent}"
    return texte


# --- Jalons, gravité, proportion ---------------------------------------------------

def jalons(ctx: ContexteJoint, maximum: int = MAX_JALONS) -> list[int]:
    """Indices (dans ctx.messages) des derniers messages qui annoncent un
    changement ou une décision, du plus ancien au plus récent."""
    trouves = [i for i, m in enumerate(ctx.messages)
               if m.auteur is not None and m.type == "text" and _mots(m.contenu) >= 4
               and _JALON.search(normaliser(m.contenu))]
    return trouves[-maximum:]


@dataclass
class Indice:
    message: MessageSource
    mot: str
    grave: bool


def indices_serieux(ctx: ContexteJoint, derniers: int = DERNIERS_SERIEUX) -> list[Indice]:
    """Mots de gravité ou de tension dans les [derniers] messages."""
    sortie = []
    for m in humains(ctx)[-derniers:]:
        if m.type != "text":
            continue
        t = normaliser(m.contenu)
        g = _GRAVE.search(t)
        if g:
            sortie.append(Indice(m, _tel_quel(m.contenu, g.group(0)), True))
            continue
        x = _TENSION.search(t)
        if x:
            sortie.append(Indice(m, _tel_quel(m.contenu, x.group(0)), False))
    return sortie


def _tel_quel(contenu: str, trouve: str) -> str:
    """Le mot tel qu'écrit (« hospitalisé »), pas sa forme normalisée."""
    for mot in re.findall(r"[\w'’]+", contenu):
        if normaliser(mot).startswith(trouve.split()[0]):
            return mot if " " not in trouve else trouve
    return trouve


def grave(ctx: ContexteJoint) -> bool:
    return any(i.grave for i in indices_serieux(ctx))


def derniers_recus(ctx: ContexteJoint) -> list[MessageSource]:
    """Derniers messages d'affilée de l'interlocuteur, si c'est lui qui a
    écrit en dernier (sinon vide)."""
    suite: list[MessageSource] = []
    for m in reversed(humains(ctx)):
        if ctx.est_moi(m.auteur) or (suite and m.auteur != suite[0].auteur):
            break
        suite.insert(0, m)
    return suite


def proportion(ctx: ContexteJoint) -> str:
    """« legere » : l'interlocuteur a écrit en dernier un message très court
    sans question (« ok 👍 », « d'accord ») — une longue réponse serait
    disproportionnée."""
    recus = derniers_recus(ctx)
    if not recus:
        return PROPORTION_NORMALE
    mots = sum(_mots(m.contenu) for m in recus if m.type == "text")
    if mots <= MOTS_LEGER_MAX and not any("?" in m.contenu for m in recus):
        return PROPORTION_LEGERE
    return PROPORTION_NORMALE


def a_repondre(ctx: ContexteJoint, mode: str, vise: MessageSource | None = None) -> MessageSource | None:
    """Message auquel les propositions répondent : celui visé par la question
    s'il vient d'un interlocuteur, sinon le dernier reçu (réponse) ou le
    dernier de l'utilisateur (relance)."""
    if vise is not None and not ctx.est_moi(vise.auteur):
        return vise
    hs = humains(ctx)
    if mode == "relance":
        return next((m for m in reversed(hs) if ctx.est_moi(m.auteur)), hs[-1] if hs else None)
    return next((m for m in reversed(hs) if not ctx.est_moi(m.auteur)), None)


def derniers_par_participant(ctx: ContexteJoint) -> list[MessageSource]:
    """Dernier message de chaque participant (groupe), du plus récent au
    plus ancien."""
    vus: dict[str, MessageSource] = {}
    for m in reversed(humains(ctx)):
        vus.setdefault(m.auteur, m)
    return list(vus.values())


# --- Suite récente : ajouts manuels et réponses déclarées envoyées ---------------

@dataclass
class Evenement:
    """Un élément de la suite récente : message (export ou ajout) ou
    réponse déclarée envoyée (non vérifiée dans WhatsApp)."""

    message: MessageSource | None = None
    declaration: dict | None = None


def _quand(valeur) -> datetime | None:
    if not valeur:
        return None
    try:
        d = datetime.fromisoformat(str(valeur).replace("Z", "+00:00"))
    except ValueError:
        return None
    return d if d.tzinfo else None


def fil(ctx: ContexteJoint, envoyees: list[dict] | None) -> list[Evenement]:
    """Messages humains + réponses déclarées envoyées, dans l'ordre réel :
    une déclaration se place avant le premier ajout manuel enregistré APRÈS
    elle (dates d'enregistrement, UTC) ; sans repère, après tout le reste.
    Une déclaration déjà présente comme message (export ou ajout) n'est
    jamais comptée deux fois."""
    suite = [Evenement(message=m) for m in humains(ctx)]
    for d in sorted(envoyees or [], key=lambda d: str(d.get("declared_at") or "")):
        if d.get("dans_export") or d.get("statut", "declaree_envoyee") != "declaree_envoyee":
            continue
        moment = _quand(d.get("declared_at"))
        position = len(suite)
        if moment is not None:
            for k, e in enumerate(suite):
                m = e.message
                if m is not None and m.manuel and m.cree_le is not None and m.cree_le > moment:
                    position = k
                    break
        suite.insert(position, Evenement(declaration=d))
    return suite


def _meme_moment(a: Evenement, b: Evenement, ctx: ContexteJoint) -> bool:
    """[a] puis [b] appartiennent-ils au même échange ? La suite récente
    (ajouts, déclarations) forme un échange à part de l'export ; dans
    l'export, une pause de plus de 6 h en ouvre un autre."""
    recent_a = a.declaration is not None or a.message.manuel
    recent_b = b.declaration is not None or b.message.manuel
    if recent_a != recent_b:
        return False
    if recent_a:
        x = a.message.cree_le if a.message is not None else _quand(a.declaration.get("declared_at"))
        y = b.message.cree_le if b.message is not None else _quand(b.declaration.get("declared_at"))
        return x is None or y is None or (y - x).total_seconds() <= 12 * 3600
    da, db = a.message.date, b.message.date
    if da is None or db is None or ctx.dates_incertaines:
        return True
    return (db - da).total_seconds() < SILENCE_NOUVEL_ECHANGE


def debut_episode(suite: list[Evenement], i: int, ctx: ContexteJoint) -> int:
    """Indice du premier événement de l'échange qui contient suite[i]."""
    k = i
    while k > 0 and _meme_moment(suite[k - 1], suite[k], ctx):
        k -= 1
    return k


def ligne_evenement(e: Evenement, ctx: ContexteJoint, numeros: dict) -> str:
    if e.declaration is not None:
        quand = str(e.declaration.get("declared_at") or "")[:16].replace("T", " ")
        return (f"(réponse que l'utilisateur DÉCLARE avoir envoyée{f', le {quand} UTC' if quand else ''}, "
                f"choisie parmi tes propositions, non vérifiée) : «{citer(str(e.declaration.get('texte') or '')[:300])}»")
    m = e.message
    k = numeros.get((m.context_id, m.ordre))
    qui = citer(m.auteur or "") + (" (utilisateur)" if ctx.est_moi(m.auteur) else "")
    origine = ", ajouté à la main" if m.manuel else ""
    return f"[{k if k else '?'}] {date_ligne(m, ctx)} · {qui}{origine} : «{citer(texte_affiche(m)[:300])}»"


def bloc_fil(ctx: ContexteJoint, envoyees: list[dict] | None, numeros: dict) -> str | None:
    """Suite la plus récente (ajouts + déclarations, ordre réel) : seulement
    s'il y a au moins une réponse déclarée envoyée à placer."""
    suite = fil(ctx, envoyees)
    if not any(e.declaration is not None for e in suite):
        return None
    debut = max(0, len(suite) - MAX_FIL)
    premiere = next(k for k, e in enumerate(suite) if e.declaration is not None)
    debut = min(debut, max(0, premiere - 1))
    lignes = ["<suite_recente>",
              f"Fin de la conversation avec « {citer(ctx.contact)} », dans l'ordre réel (export, ajouts à la main "
              "et réponses déclarées envoyées) ; un message reçu APRÈS une réponse déclarée y réagit probablement :"]
    lignes += [f"- {ligne_evenement(e, ctx, numeros)}" for e in suite[debut:]]
    lignes.append("</suite_recente>")
    return "\n".join(lignes)


# --- Faits pour l'aperçu (réponse principale) -------------------------------------

def faits(ctx: ContexteJoint, compact: bool = False) -> list[str]:
    """Lignes ajoutées à l'aperçu : habitudes, jalons, derniers messages par
    participant (groupe), indices de sérieux, inconnues. [compact] (budget
    serré) : habitudes de l'utilisateur et du dernier interlocuteur
    seulement, deux jalons, pas de liste par participant."""
    lignes: list[str] = []
    if compact:
        recu = a_repondre(ctx, "reponse")
        hs = habitudes(ctx, [a for a in dict.fromkeys([ctx.moi, recu.auteur if recu else None]) if a])
        for h in hs:
            h.expressions = h.expressions[:2]
    else:
        hs = habitudes(ctx)
    if hs:
        lignes.append("- Habitudes d'écriture observées (tendances, la situation actuelle peut s'en écarter) :")
        lignes += [f"  · {ligne_habitude(h, ctx)}" for h in hs]
    js = jalons(ctx, 2 if compact else MAX_JALONS)
    if js:
        lignes.append("- Changements ou décisions annoncés (les plus récents ; la dernière décision écrite prime) :")
        for i in js:
            m = ctx.messages[i]
            texte = texte_affiche(m)
            texte = texte[:110].rstrip() + ("…" if len(texte) > 110 else "")
            lignes.append(f"  · {date_ligne(m, ctx)} · {citer(m.auteur or '')} : «{citer(texte)}»")
    if ctx.groupe and not compact:
        derniers = derniers_par_participant(ctx)[:8]
        if derniers:
            lignes.append("- Dernier message de chaque participant : " + " ; ".join(
                f"{citer(m.auteur)} ({date_ligne(m, ctx)})" for m in derniers))
    indices = indices_serieux(ctx)
    if indices:
        lignes.append("- Indices de sérieux ou de tension dans les derniers messages (à vérifier dans le contexte, "
                      "un émoji peut les adoucir) : " + " ; ".join(
                          f"«{citer(i.mot)}» ({citer(i.message.auteur or '')})" for i in indices[-3:]))
    inconnues = []
    sans_date = sum(1 for m in ctx.messages if m.manuel and m.date is None)
    if sans_date:
        inconnues.append(f"date réelle de {sans_date} message(s) ajouté(s) à la main (ordre connu)")
    if ctx.dates_incertaines:
        inconnues.append("ordre jour/mois des dates")
    if ctx.moi is None:
        inconnues.append("qui est l'utilisateur dans cette discussion")
    if inconnues:
        lignes.append("- Inconnu : " + " ; ".join(inconnues))
    return lignes
