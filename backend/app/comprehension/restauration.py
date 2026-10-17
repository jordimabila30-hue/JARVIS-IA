"""Références enregistrées : lecture et restauration.

Stockage : `messages.attachments` (colonne JSON déjà présente dans le
schéma, jusqu'ici inutilisée), dans la MÊME ligne que la réponse de JARVIS,
donc écrite en une seule insertion avec elle :

  [{"type": "reference_whatsapp", "context_id": "…",
    "context_message_id": "…", "message_order": 12, "rang": 0,
    "position": 143},
   {"type": "note_references", "text": "…"},
   {"type": "propositions_reponse", "mode": "reponse", "tons": […]}]

Les propositions de réponse (phase 3) sont le texte de JARVIS lui-même :
rendues telles qu'enregistrées (forme revalidée), avec la réponse.

Seuls les identifiants sont gardés. À la lecture, chaque référence est
relue dans `context_messages`, filtrée par le compte du JWT : un message
supprimé (pièce jointe retirée) ou d'un autre compte n'est jamais renvoyé ;
auteur, date et texte viennent toujours de Supabase.
"""

from . import propositions
from .extraits import ContexteJoint
from .moteur import contexte_joint, message_source
from .references import Fourni, charge

TYPE_REFERENCE = "reference_whatsapp"
TYPE_NOTE = "note_references"


def entrees(attachments) -> list[dict]:
    return [a for a in (attachments or []) if isinstance(a, dict) and a.get("type") == TYPE_REFERENCE]


def note(attachments) -> str | None:
    for a in attachments or []:
        if isinstance(a, dict) and a.get("type") == TYPE_NOTE and isinstance(a.get("text"), str):
            return a["text"]
    return None


def cites(lignes: list[dict]) -> dict[str, set[int]]:
    """Contexte → rangs cités par ces réponses (« pourquoi tu dis ça ? »),
    appuis des propositions de réponse compris."""
    resultat: dict[str, set[int]] = {}
    for ligne in lignes:
        p = propositions.lues(ligne.get("attachments"))
        for e in [*entrees(ligne.get("attachments")), *(propositions.appuis(p) if p else [])]:
            try:
                resultat.setdefault(str(e["context_id"]), set()).add(int(e["message_order"]))
            except (KeyError, TypeError, ValueError):
                continue
    return resultat


async def references_conversation(supabase, user_id: str, conversation_id: str) -> list[dict]:
    """[{message_id, references, note}] pour les réponses du chat qui en
    ont, références vérifiées de nouveau dans Supabase."""
    lignes = await supabase.get_assistant_attachments(conversation_id, user_id)
    if not lignes:
        return []
    contextes: dict[str, ContexteJoint] = {
        str(c["id"]): contexte_joint(c, "A") for c in await supabase.list_contexts(conversation_id, user_id)
    }
    ids = sorted({
        str(e["context_message_id"])
        for l in lignes for e in entrees(l.get("attachments"))
        if e.get("context_message_id") and str(e.get("context_id")) in contextes
    })
    messages = {
        str(m["id"]): m for m in await supabase.get_context_messages_by_ids(ids, user_id)
    }
    resultat = []
    for l in lignes:
        refs = []
        for e in sorted(entrees(l.get("attachments")), key=lambda e: e.get("rang", 0)):
            ctx = contextes.get(str(e.get("context_id")))
            m = messages.get(str(e.get("context_message_id")))
            # Message absent, ou rattaché à un autre contexte : jamais affiché.
            if ctx is None or m is None or str(m.get("context_id")) != ctx.id:
                continue
            f = Fourni(0, message_source(ctx, m), ctx)
            refs.append(charge(f, len(refs), int(e.get("position") or 0)))
        texte = note(l.get("attachments"))
        props = propositions.lues(l.get("attachments"), str(l["id"]))
        if refs or texte or props:
            resultat.append({"message_id": l["id"], "references": refs, "note": texte,
                             "propositions": props})
    return resultat
