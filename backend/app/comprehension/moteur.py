"""Orchestration du moteur de compréhension conversationnelle.

Pour une question posée dans un chat JARVIS qui a des conversations
WhatsApp jointes :

  1. pièces jointes du chat (filtrées par le compte du JWT) ;
  2. pièces jointes visées : celle de la consigne (`reply_to`), celles
     dont le contact est nommé, sinon la plus récente (ou toutes si elles
     concernent le même contact) ;
  3. leurs messages (Supabase, mis en cache dans Redis : une pièce jointe
     ne change jamais après son enregistrement) ;
  4. aperçu calculé sur tous les messages + extraits choisis selon la
     question, dans le budget de tokens du modèle ;
  5. messages pour le modèle : instructions générales de JARVIS +
     instructions du moteur + bloc de données délimité, historique du chat
     (borné), question.

Le contenu des messages n'est jamais journalisé.
"""

import json
import logging
from dataclasses import dataclass, field
from datetime import date, datetime

from redis.asyncio import Redis
from redis.exceptions import RedisError

from ..config import Settings
from ..supabase_client import SupabaseAdmin
from . import ciblage as ciblage_mod, etat, extraits, propositions, reperes
from .extraits import ContexteJoint, MessageSource, estimer_tokens
from .references import Fourni
from .instructions import INSTRUCTIONS_COMPREHENSION, NOTE_SANS_CONSENTEMENT, bloc_donnees

logger = logging.getLogger(__name__)

_LETTRES = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
_PAGE = 1000
LONGUEUR_MAX_HISTORIQUE = 2000   # caractères d'un ancien message du chat
# Instructions fixes (prose française) : ~4 caractères par token mesurés ;
# l'estimation prudente des messages (3) réservait ~700 tokens de trop aux
# dépens des extraits WhatsApp.
TOKENS_INSTRUCTIONS = len(INSTRUCTIONS_COMPREHENSION) // 4 + 1
# Place minimale des messages WhatsApp : une longue partie fixe (historique,
# mémoire, propositions précédentes) ne doit jamais réduire l'analyse à
# quatre messages (vu en réel avec 200).
PLANCHER_MESSAGES = 1000


def cle_cache(context_id: str) -> str:
    # v2 : lignes avec leur identifiant `id` (références vérifiées) ;
    # v3 : provenance (`origin`, phase 5). Vidé à chaque ajout manuel.
    return f"wactx:v3:{context_id}:messages"


@dataclass
class Preparation:
    """Ce qui part vers le modèle, et ce qui a servi (phase 2 : références)."""

    messages: list[dict]
    contextes: list[str] = field(default_factory=list)       # pièces jointes fournies
    references: list[MessageSource] = field(default_factory=list)
    # Numéro de la requête ([12]) → message réellement fourni : seule table
    # qui permet de résoudre un repère du modèle.
    fournis: dict[int, Fourni] = field(default_factory=dict)
    complete: bool = True
    tokens_estimes: int = 0
    # Message visé, choisi AVANT l'appel à l'IA (ciblage.py).
    ciblage: "ciblage_mod.Ciblage | None" = None


def _date(valeur) -> datetime | None:
    if not valeur:
        return None
    try:
        d = datetime.fromisoformat(str(valeur))
    except ValueError:
        return None
    # Heure locale de l'export : jamais de fuseau ajouté ou converti.
    return d.replace(tzinfo=None)


def _nombre(ligne: dict) -> int:
    embarque = ligne.get("context_messages") or [{"count": 0}]
    return int(embarque[0].get("count", 0))


def contexte_joint(ligne: dict, lettre: str) -> ContexteJoint:
    return ContexteJoint(
        id=str(ligne["id"]),
        lettre=lettre,
        contact=ligne.get("contact_name") or "Contact",
        groupe=bool(ligne.get("is_group")),
        moi=ligne.get("current_user_name"),
        participants=list(ligne.get("participants") or []),
        debut=_date(ligne.get("period_start")),
        fin=_date(ligne.get("period_end")),
        dates_incertaines=bool(ligne.get("dates_uncertain")),
        joint_le=str(ligne.get("created_at") or ""),
        consigne_id=str(ligne["message_id"]) if ligne.get("message_id") else None,
        nombre=_nombre(ligne),
    )


def message_source(ctx: ContexteJoint, r: dict) -> MessageSource:
    return MessageSource(
        context_id=ctx.id,
        lettre=ctx.lettre,
        id=str(r["id"]) if r.get("id") else None,
        ordre=int(r["message_order"]),
        ordre_source=r.get("source_order"),
        auteur=r.get("author"),
        contenu=r.get("content") or "",
        type=r.get("kind") or "text",
        type_media=r.get("media_type"),
        date=_date(r.get("sent_at")),
        date_brute=r.get("sent_at_raw") or "",
        origine=r.get("origin") or "export",
        cree_le=_instant(r.get("created_at")) if (r.get("origin") or "export") != "export" else None,
    )


def _instant(valeur) -> datetime | None:
    """Instant d'enregistrement (UTC) d'un ajout manuel : jamais une date
    WhatsApp, seulement l'ordre par rapport aux déclarations."""
    if not valeur:
        return None
    try:
        d = datetime.fromisoformat(str(valeur).replace("Z", "+00:00"))
    except ValueError:
        return None
    return d if d.tzinfo else None


def borner_historique(historique: list[dict], budget: int) -> list[dict]:
    """Les derniers messages du chat qui tiennent dans [budget] tokens (les
    plus récents d'abord ; un message très long est raccourci)."""
    garde: list[dict] = []
    depense = 0
    for m in reversed(historique):
        contenu = m["content"]
        if len(contenu) > LONGUEUR_MAX_HISTORIQUE:
            contenu = "[…] " + contenu[-LONGUEUR_MAX_HISTORIQUE:]
        cout = estimer_tokens(contenu) + 4
        if depense + cout > budget:
            break
        garde.append({"role": m["role"], "content": contenu})
        depense += cout
    return list(reversed(garde))


def _mentionne(ctx: ContexteJoint, question: str) -> bool:
    q = f" {reperes.normaliser(question)} "
    noms = [ctx.contact, *(p for p in ctx.participants if p != ctx.moi)]
    for nom in noms:
        for mot in reperes.normaliser(nom).split():
            if len(mot) >= 3 and f" {mot} " in q.replace("?", " ").replace(",", " ").replace("'", " "):
                return True
    return False


def choisir(contextes: list[ContexteJoint], question: str, reponse_a: str | None) -> list[ContexteJoint]:
    """Pièces jointes visées par la question (jamais vide si [contextes])."""
    if reponse_a:
        cible = [c for c in contextes if c.consigne_id == reponse_a]
        if cible:
            return cible
    nommes = [c for c in contextes if _mentionne(c, question)]
    if nommes:
        return nommes
    dernier = contextes[-1]
    meme = [c for c in contextes if reperes.normaliser(c.contact) == reperes.normaliser(dernier.contact)]
    return meme


@dataclass
class MoteurComprehension:
    supabase: SupabaseAdmin
    redis: Redis
    settings: Settings

    async def contextes(self, user_id: str, conversation_id: str) -> list[ContexteJoint]:
        """Pièces jointes du chat, de la plus ancienne à la plus récente."""
        lignes = await self.supabase.list_contexts(conversation_id, user_id)
        return [contexte_joint(l, _LETTRES[i % 26]) for i, l in enumerate(lignes)]

    async def charger(self, ctx: ContexteJoint, user_id: str) -> None:
        """Messages de la pièce jointe, dans l'ordre original."""
        lignes = None
        try:
            brut = await self.redis.get(cle_cache(ctx.id))
            if brut:
                lignes = json.loads(brut)
        except (RedisError, ValueError):
            logger.warning("Cache des pièces jointes illisible", exc_info=True)
        if lignes is None:
            lignes = []
            apres = -1
            while True:
                page = await self.supabase.list_context_messages(
                    ctx.id, user_id, after=apres, limit=_PAGE
                )
                lignes.extend(page)
                if len(page) < _PAGE:
                    break
                apres = page[-1]["message_order"]
            try:
                await self.redis.set(
                    cle_cache(ctx.id),
                    json.dumps(lignes, ensure_ascii=False, default=str),
                    ex=self.settings.comprehension_cache_ttl,
                )
            except RedisError:
                logger.warning("Pièce jointe non mise en cache", exc_info=True)
        ctx.messages = [message_source(ctx, r) for r in lignes]

    def preparer(
        self,
        *,
        systeme: str,
        contextes: list[ContexteJoint],
        cibles: list[ContexteJoint],
        historique: list[dict],
        question: str,
        aujourd_hui: date,
        budget: int,
        cites: dict[str, set[int]] | None = None,
        propositions_faites: dict | None = None,
        ton_affiche: str | None = None,
        envoyees: dict[str, list[dict]] | None = None,
        longueur_affichee: str | None = None,
        ciblage: "ciblage_mod.Ciblage | None" = None,
    ) -> Preparation:
        """Messages pour le modèle (les [cibles] ont leurs messages chargés).
        [cites] : contexte → rangs cités par les réponses précédentes.
        [propositions_faites] : dernières propositions de réponse (phase 3), et le
        ton que l'utilisateur regarde."""
        precedentes = [m["content"] for m in historique if m["role"] == "user"]
        r = reperes.analyser(question, precedentes, aujourd_hui)

        if ciblage is not None:
            # Anciennes réponses sur « le dernier message » : retirées, les
            # faits enregistrés (message visé) les remplacent.
            historique = ciblage_mod.retirer_anciens_derniers(historique)
        historique = borner_historique(historique, self.settings.comprehension_history_tokens)
        actives = {c.id for c in cibles}
        catalogue = "\n".join(extraits.fiche(c, c.id in actives) for c in contextes)
        fixe = (
            estimer_tokens(systeme) + TOKENS_INSTRUCTIONS
            + estimer_tokens(catalogue) + estimer_tokens(question)
            + sum(estimer_tokens(m["content"]) + 4 for m in historique) + 80
        )
        # Aperçu = faits comptés sur tout + état partagé (habitudes, jalons,
        # indices de sérieux, inconnues : etat.py), le même que reçoivent les
        # lots de propositions.
        apercus = {c.id: "\n".join([extraits.apercu(c, aujourd_hui), *etat.faits(c)]) for c in cibles}
        cout_apercus = sum(estimer_tokens(a) + 30 for a in apercus.values())
        if budget - fixe - cout_apercus < PLANCHER_MESSAGES:
            # Budget serré (aide à répondre sur GroqCloud) : état compact,
            # plutôt que dépasser la limite ou sacrifier les messages.
            apercus = {c.id: "\n".join([extraits.apercu(c, aujourd_hui), *etat.faits(c, compact=True)])
                       for c in cibles}
            cout_apercus = sum(estimer_tokens(a) + 30 for a in apercus.values())
        fixe += cout_apercus
        memoires = [propositions.bloc_memoire(envoyees[c.id], c.contact)
                    for c in cibles if envoyees and envoyees.get(c.id)]
        fixe += sum(estimer_tokens(m) + 10 for m in memoires)
        # Suite récente (ajouts + réponses déclarées envoyées, ordre réel).
        fixe += sum(estimer_tokens(etat.bloc_fil(c, (envoyees or {}).get(c.id), {}) or "") for c in cibles)
        if ciblage is not None:
            fixe += 120   # bloc du message visé (message et ce qui précède)
        if propositions_faites:
            fixe += estimer_tokens(propositions.bloc_precedentes(propositions_faites, {}, ton_affiche, question, longueur_affichee)) + 20
        disponible = max(PLANCHER_MESSAGES, budget - fixe)

        total = sum(len(c.messages) for c in cibles) or 1
        sections: list[str] = []
        references: list[MessageSource] = []
        fournis: dict[int, Fourni] = {}
        complete = True
        for c in cibles:
            part = int(disponible * len(c.messages) / total)
            rangs = (cites or {}).get(c.id) or set()
            forces = [i for i, m in enumerate(c.messages) if m.ordre in rangs]
            sel = extraits.selectionner(c, r, part, forces, etat.jalons(c))
            complete &= sel.complete and len(c.messages) >= c.nombre
            if sel.complete and len(c.messages) >= c.nombre:
                couverture = f"conversation entière ({len(c.messages)} messages)"
            else:
                couverture = (
                    f"EXTRAITS seulement : {len(sel.indices)} messages sur {c.nombre} "
                    f"(choisis : {', '.join(sel.raisons)})"
                )
                if len(c.messages) < c.nombre:
                    couverture += f" ; {c.nombre - len(c.messages)} messages illisibles"
            sections.append(
                f"<apercu piece=\"{c.lettre}\">\nAperçu calculé sur les {len(c.messages)} messages "
                f"de la pièce jointe {c.lettre} :\n{apercus[c.id]}\n</apercu>\n"
                f"<messages piece=\"{c.lettre}\" couverture=\"{couverture}\">\n"
                f"{extraits.passages(c.messages, sel.indices, c, len(fournis) + 1)}\n</messages>"
            )
            for i in sel.indices:
                numero = len(fournis) + 1
                fournis[numero] = Fourni(numero, c.messages[i], c)
            references.extend(c.messages[i] for i in sel.indices)

        contenu_systeme = (
            f"{systeme}\n\n{INSTRUCTIONS_COMPREHENSION}\n"
            f"Date du jour (serveur) : {aujourd_hui.strftime('%d/%m/%Y')}.\n\n"
            f"{bloc_donnees(catalogue, sections)}"
        )
        # Propositions déjà faites : juste avant la question (essai réel :
        # en fin de long message système, le modèle les ignorait et citait
        # une proposition inventée).
        blocs = [*memoires]
        vise = ciblage_mod.bloc(ciblage, fournis, envoyees)
        if vise:
            blocs.append(vise)      # il contient déjà la suite qui précède le message visé
        else:
            numeros = {(f.message.context_id, f.message.ordre): n for n, f in fournis.items()}
            for c in cibles:
                suite = etat.bloc_fil(c, (envoyees or {}).get(c.id), numeros)
                if suite:
                    blocs.append(suite)
        if propositions_faites:
            blocs.append(propositions.bloc_precedentes(propositions_faites, fournis, ton_affiche, question,
                                                    longueur_affichee))
        rappel = [{"role": "system", "content": "\n\n".join(blocs)}] if blocs else []
        messages = [
            {"role": "system", "content": contenu_systeme},
            *historique,
            *rappel,
            {"role": "user", "content": question},
        ]
        return Preparation(
            messages=messages,
            contextes=[c.id for c in cibles],
            references=references,
            fournis=fournis,
            complete=complete,
            ciblage=ciblage,
            # Même mesure que le budget : instructions à 4 caractères par token.
            tokens_estimes=sum(estimer_tokens(m["content"]) + 4 for m in messages)
            - (estimer_tokens(INSTRUCTIONS_COMPREHENSION) - TOKENS_INSTRUCTIONS),
        )

    def sans_consentement(self, *, systeme: str, historique: list[dict], question: str) -> Preparation:
        """Chat avec pièces jointes, analyse refusée : aucun contenu WhatsApp."""
        historique = borner_historique(historique, self.settings.comprehension_history_tokens)
        messages = [
            {"role": "system", "content": f"{systeme}\n\n{NOTE_SANS_CONSENTEMENT}"},
            *historique,
            {"role": "user", "content": question},
        ]
        return Preparation(messages=messages, complete=True,
                           tokens_estimes=sum(estimer_tokens(m["content"]) for m in messages))
