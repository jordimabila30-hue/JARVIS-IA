"""Essai RÉEL (manuel, une requête GroqCloud) du ciblage du dernier message.

Reproduit le cas vu le 2026-10-16 : conversation fictive de Lina
(tests_whatsapp/), ajouts manuels sans date, et TROIS anciennes réponses
fausses de JARVIS dans l'historique (le cas qui ancrait le modèle).

    docker run --rm -v "<dépôt>:/repo" -w /repo/backend --env-file .env \
        --entrypoint python backend-api tests/essai_ciblage_reel.py
"""

import asyncio
import sys
import time
from datetime import date, datetime

sys.path.insert(0, "/repo/backend")
sys.path.insert(0, "/repo/backend/tests")

from app.api.v1.chat import Ton, build_system_prompt, get_openai  # noqa: E402
from app.comprehension import ciblage  # noqa: E402
from app.comprehension.attribution import CorrecteurAttributions  # noqa: E402
from app.comprehension.moteur import MoteurComprehension, message_source  # noqa: E402
from app.comprehension.references import FiltreReperes, verifier  # noqa: E402
from app.config import get_settings  # noqa: E402
from test_campagne import contexte  # noqa: E402

AJOUTS = [
    ("Lina Moreau", "Ah bon ? Et tu comptais me le dire quand ?", "manual_received"),
    ("Alex Martin", "Finalement je serai disponible samedi.", "manual_sent"),
    ("Lina Moreau", "je t'aime mon amie", "manual_received"),
    ("Lina Moreau", "Ok, mais la prochaine fois previens-moi plus tot ! Promis ?", "manual_received"),
    ("Lina Moreau", "Bon, je te pardonne pour cette fois.", "manual_received"),
]
QUESTION = "JARVIS, que penses-tu de la dernière réponse de Lina ?"
FAUSSE = ("Le dernier message de Lina (« Alors on va devoir continuer le traitement. Tous les soirs. "
          "C'est pas une blague hein 😊 ») a un ton à la fois léger et bienveillant.")


async def main():
    settings = get_settings()
    ctx = contexte("JARVIS_TEST_SENTIMENTAL.zip")
    for auteur, texte, origine in AJOUTS:
        ordre = ctx.messages[-1].ordre + 1
        ctx.messages.append(message_source(ctx, {
            "id": f"ajout-{ordre}", "message_order": ordre, "author": auteur, "content": texte,
            "kind": "text", "sent_at": None, "sent_at_raw": "", "origin": origine}))
    historique = []
    for _ in range(3):
        historique += [{"role": "user", "content": QUESTION}, {"role": "assistant", "content": FAUSSE}]
    debut = time.perf_counter()
    visee = ciblage.cibler(QUESTION, [ctx], [h["content"] for h in historique if h["role"] == "user"])
    print("CIBLE (avant l'appel IA) :", visee.cible.genre, visee.cible.participant,
          visee.cible.message.id, repr(visee.cible.message.contenu))
    p = MoteurComprehension(None, None, settings).preparer(
        systeme=build_system_prompt(Ton.naturel, None, datetime(2026, 10, 16)), contextes=[ctx], cibles=[ctx],
        historique=historique, question=QUESTION, aujourd_hui=date(2026, 10, 16),
        budget=settings.comprehension_budget_tokens, cites=ciblage.voisins(visee), ciblage=visee)
    print(f"préparation {1000 * (time.perf_counter() - debut):.0f} ms, {len(p.fournis)} messages fournis, "
          f"historique gardé : {len(p.messages) - 3} message(s)")
    client = get_openai().with_options(max_retries=0)
    appel = time.perf_counter()
    r = await client.chat.completions.create(model=settings.openai_model, messages=p.messages,
                                             max_tokens=settings.comprehension_max_output_tokens)
    brut = r.choices[0].message.content or ""
    c = CorrecteurAttributions(p.fournis)
    f = FiltreReperes(c)
    texte = f.ajouter(brut) + f.terminer()
    v = verifier(texte, f.reperes, p.fournis)
    print(f"GroqCloud : {r.usage.prompt_tokens} + {r.usage.completion_tokens} tokens, "
          f"{time.perf_counter() - appel:.1f} s")
    print("RÉPONSE :", texte)
    for ref in v.references:
        print("   ↳", ref["author"], "·", ref["excerpt"], "·", ref.get("origin"))
    juste = "pardonne" in texte.lower() and "continuer le traitement" not in texte.lower()
    print("VERDICT :", "JUSTE" if juste else "À RELIRE")


asyncio.run(main())
