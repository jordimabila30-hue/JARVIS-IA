"""Diagnostic (manuel, AUCUN appel à l'IA) : ce que la route de chat
préparerait pour une question dans un chat réel (lecture seule Supabase).

    docker run --rm -v "$PWD:/app" -w /app --env-file .env -e CHAT=<uuid> -e USER=<uuid> \
        -e QUESTION="..." --entrypoint python backend-api tests/diag_preparation.py
"""

import asyncio
import os
import sys
from datetime import datetime, timezone

sys.path.insert(0, "/app")

from redis.exceptions import RedisError  # noqa: E402

from app.api.v1.chat import Ton, build_system_prompt  # noqa: E402
from app.comprehension import ciblage, extraits, memoire, propositions as aide, reperes, restauration  # noqa: E402
from app.comprehension.extraits import estimer_tokens  # noqa: E402
from app.comprehension.moteur import MoteurComprehension, TOKENS_INSTRUCTIONS, borner_historique, choisir  # noqa: E402
from app.config import get_settings  # noqa: E402
from app.supabase_client import init_supabase  # noqa: E402


class SansCache:
    async def get(self, *_):
        raise RedisError("diagnostic sans cache")

    async def set(self, *_, **__):
        raise RedisError("diagnostic sans cache")


async def main():
    s = get_settings()
    supa = init_supabase(s.supabase_url, s.supabase_service_role_key)
    chat, user, q = os.environ["CHAT"], os.environ["USER"], os.environ["QUESTION"]
    m = MoteurComprehension(supa, SansCache(), s)
    contextes = await m.contextes(user, chat)
    cibles = choisir(contextes, q, None)
    for c in cibles:
        await m.charger(c, user)
    historique = [{"role": r["role"], "content": r["content"]} for r in await supa.get_recent_messages(chat, 20)]
    recentes = await supa.get_assistant_attachments(chat, user, limit=3)
    cites = restauration.cites(recentes[:2])
    precedentes = next((p for p in (aide.lues(l.get("attachments"), str(l["id"])) for l in recentes)
                        if p and p.get("tons")), None)
    envoyees = await memoire.pour_contacts(supa, user, cibles)
    now = datetime.now(timezone.utc)
    systeme = build_system_prompt(Ton.naturel, None, now)
    r = reperes.analyser(q, [h["content"] for h in historique if h["role"] == "user"], now.date())
    print("repères :", r)
    hist = borner_historique(historique, s.comprehension_history_tokens)
    actives = {c.id for c in cibles}
    catalogue = "\n".join(extraits.fiche(c, c.id in actives) for c in contextes)
    parts = {
        "systeme": estimer_tokens(systeme), "instructions": TOKENS_INSTRUCTIONS,
        "catalogue": estimer_tokens(catalogue), "question": estimer_tokens(q),
        "historique": sum(estimer_tokens(h["content"]) + 4 for h in hist),
        "apercus": sum(estimer_tokens(extraits.apercu(c, now.date())) + 30 for c in cibles),
        "memoires": sum(estimer_tokens(aide.bloc_memoire(envoyees[c.id], c.contact)) + 10
                        for c in cibles if envoyees and envoyees.get(c.id)),
        "precedentes": (estimer_tokens(aide.bloc_precedentes(precedentes, {}, None, q)) + 20) if precedentes else 0,
    }
    print("parts fixes (tokens estimés) :", parts, "total", sum(parts.values()) + 80)
    print("messages de l'historique gardés :", len(hist), "sur", len(historique))
    visee = ciblage.cibler(q, cibles, [h["content"] for h in historique if h["role"] == "user"])
    for cid, rangs in ciblage.voisins(visee).items():
        cites.setdefault(cid, set()).update(rangs)
    if visee and visee.cible:
        print("CIBLE :", visee.cible.genre, visee.cible.participant, "rang", visee.cible.message.ordre,
              visee.cible.message.origine, visee.cible.message.id, repr(visee.cible.message.contenu[:60]))
    elif visee:
        print("CLARIFICATION :", visee.ambigus)
    p = m.preparer(systeme=systeme, contextes=contextes, cibles=cibles, historique=historique, question=q,
                   aujourd_hui=now.date(), budget=s.comprehension_budget_tokens, cites=cites,
                   propositions_faites=precedentes, envoyees=envoyees, ciblage=visee)
    print("fournis :", len(p.fournis), "complète :", p.complete, "≈", p.tokens_estimes, "tokens")
    for n, f in p.fournis.items():
        print(f"  [{n}] ordre {f.message.ordre} · {f.message.origine} · {f.message.auteur} · {f.message.contenu[:50]!r}")
    for c in cibles:
        print("dernier (ordre) :", c.messages[-1].ordre, c.messages[-1].origine, c.messages[-1].contenu[:40])
    if os.environ.get("TEXTE"):
        systeme_complet = p.messages[0]["content"]
        for ligne in systeme_complet.splitlines():
            if ligne.startswith(("[1", "[2", "- Dernier", "- Situation", "Situation", "<messages", "- P")):
                print("   |", ligne[:170])
        print("   rappel :", p.messages[-2]["content"][-900:] if p.messages[-2]["role"] == "system" else None)
        print("   historique envoyé :", [(m["role"], m["content"][:60]) for m in p.messages[1:-1]][-4:])


asyncio.run(main())
