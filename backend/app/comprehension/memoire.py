"""Mémoire des réponses déclarées envoyées (phase 4).

Un appui long sur une proposition = l'utilisateur DÉCLARE avoir envoyé ce
message à son interlocuteur. JARVIS ne l'envoie pas et ne le vérifie pas
dans WhatsApp. Trois choses restent distinctes :
  - message WhatsApp original : `context_messages` (importé) ;
  - proposition de JARVIS : `messages.attachments`, type
    `propositions_reponse` ;
  - réponse déclarée envoyée : `messages.attachments` de la MÊME réponse,
    type `reponse_envoyee` (statut `declaree_envoyee` ou `annulee`).

Pas de migration : la colonne JSON existe, la réponse appartient au compte
(filtre `user_id` explicite, service_role) et au chat. Idempotent : une
proposition n'a qu'une déclaration (redéclarer une déclaration active la
renvoie telle quelle ; une annulation est gardée, avec sa date).
"""

from datetime import datetime, timezone

from . import propositions as aide
from .reperes import normaliser

MAX_MEMOIRE = 8


class PropositionIntrouvable(Exception):
    pass


class DejaChoisi(Exception):
    """Phase 5.1 : une autre proposition de CET ensemble est déjà déclarée
    envoyée (un seul choix actif, garanti par la base)."""

    def __init__(self, proposition_id: str | None) -> None:
        super().__init__(proposition_id)
        self.proposition_id = proposition_id


async def _cible(supabase, user_id: str, conversation_id: str, message_id: str, proposition_id: str):
    ligne = await supabase.get_assistant_message(message_id, conversation_id, user_id)
    if ligne is None:
        raise PropositionIntrouvable()
    attachments = list(ligne.get("attachments") or [])
    p = aide.lues(attachments, message_id)
    trouve = aide.trouver(p, proposition_id) if p else None
    if trouve is None:
        raise PropositionIntrouvable()
    return attachments, p, trouve


def _etat(d: dict | None) -> dict:
    actif = d is not None and d.get("statut") == "declaree_envoyee"
    return {"envoyee": actif, "declared_at": d.get("declared_at") if actif else None,
            "cancelled_at": d.get("cancelled_at") if d else None}


async def declarer(supabase, user_id: str, conversation_id: str, message_id: str, proposition_id: str) -> dict:
    """Un seul choix actif par ensemble (tous tons et longueurs) : la
    fonction SQL verrouille la réponse ; même proposition = idempotent."""
    attachments, p, (ton, prop) = await _cible(supabase, user_id, conversation_id, message_id, proposition_id)
    active = next((d for d in aide.declarations(attachments) if d.get("statut") == "declaree_envoyee"), None)
    if active is not None:
        if active["proposition_id"] == proposition_id:
            return _etat(active)          # double appui : aucun doublon
        raise DejaChoisi(active["proposition_id"])
    contact, groupe = None, False
    for c in await supabase.list_contexts(conversation_id, user_id):
        if str(c["id"]) == str(p.get("context_id")):
            contact, groupe = c.get("contact_name"), bool(c.get("is_group"))
    maintenant = datetime.now(timezone.utc).isoformat()
    entree = {
        "type": aide.TYPE_ENVOYEE,
        "statut": "declaree_envoyee",
        "proposition_id": proposition_id,
        "texte": prop["texte"],
        "ton": ton["nom"],
        "longueur": prop.get("longueur"),
        "rang": prop.get("rang"),
        "context_id": p.get("context_id"),
        "contact": contact,
        "groupe": groupe,
        "conversation_id": conversation_id,
        "message_id": message_id,
        "user_id": user_id,
        "declared_at": maintenant,
        "cancelled_at": None,
    }
    r = await supabase.declare_reply(user_id, conversation_id, message_id, entree)
    if r.get("statut") == "deja_choisi":
        raise DejaChoisi((r.get("entree") or {}).get("proposition_id"))
    return _etat(r.get("entree") or entree)


async def annuler(supabase, user_id: str, conversation_id: str, message_id: str, proposition_id: str) -> dict:
    attachments, _, _ = await _cible(supabase, user_id, conversation_id, message_id, proposition_id)
    r = await supabase.cancel_reply(user_id, conversation_id, message_id, proposition_id,
                                    datetime.now(timezone.utc).isoformat())
    if r.get("statut") == "annulee":
        return _etat(r.get("entree"))
    d = next((d for d in aide.declarations(attachments) if d["proposition_id"] == proposition_id), None)
    return _etat(d)


async def pour_contacts(supabase, user_id: str, contextes) -> dict[str, list[dict]]:
    """Contexte visé → réponses déclarées envoyées à CE contact (tous les
    chats du compte : même pièce jointe, ou même nom de contact), les plus
    récentes d'abord. Une réponse retrouvée telle quelle parmi les
    messages de l'utilisateur dans l'export est marquée `dans_export`."""
    if not contextes:
        return {}
    lignes = await supabase.list_declared_replies(user_id)
    toutes = [d for l in lignes for d in aide.declarations(l.get("attachments"))
              if d.get("statut") == "declaree_envoyee" and d.get("user_id") in (None, user_id)]
    toutes.sort(key=lambda d: str(d.get("declared_at") or ""), reverse=True)
    resultat: dict[str, list[dict]] = {}
    for c in contextes:
        nom = normaliser(c.contact)
        siennes = [d for d in toutes
                   if d.get("context_id") == c.id or (d.get("contact") and normaliser(d["contact"]) == nom)]
        if not siennes:
            continue
        miens = {normaliser(m.contenu) for m in c.messages if c.est_moi(m.auteur) and m.type == "text"}
        resultat[c.id] = [{**d, "dans_export": normaliser(str(d.get("texte") or "")) in miens}
                          for d in siennes[:MAX_MEMOIRE]]
    return resultat
