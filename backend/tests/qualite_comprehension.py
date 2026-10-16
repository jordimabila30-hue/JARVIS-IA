"""Essai de qualité RÉEL (pas un test automatique) : conversations fictives
envoyées au modèle configuré (GroqCloud), questions enchaînées.

    docker run --rm -v "$PWD:/app" -w /app --env-file .env --entrypoint \
        python backend-api tests/qualite_comprehension.py

Consomme du quota GroqCloud ; à lancer à la main.
"""

import asyncio
import sys
import time
from datetime import date, datetime, timedelta

sys.path.insert(0, "/app")

from app.api.v1.chat import Ton, build_system_prompt, completer_ensemble, get_openai  # noqa: E402
from app.comprehension import generation  # noqa: E402
from app.comprehension.moteur import MoteurComprehension, contexte_joint, message_source  # noqa: E402
from app.comprehension import propositions as aide, reperes  # noqa: E402
from app.comprehension.attribution import CorrecteurAttributions  # noqa: E402
from app.comprehension.references import FiltreReperes, verifier  # noqa: E402
from app.config import get_settings  # noqa: E402

DEBUT = datetime(2026, 10, 1, 8, 30)
ECHANGES = [
    # jour, heure, auteur, texte
    (0, "08:30", "Pepper Potts", "Bonjour Tony. Rappel : réunion du conseil à 10 h, c'est important."),
    (0, "09:55", "Tony Stark", "J'y serai. Probablement. Peut-être. 😇"),
    (0, "10:40", "Pepper Potts", "Tu n'y étais pas. Le conseil t'a attendu 40 minutes."),
    (0, "10:42", "Tony Stark", "J'étais en train de sauver le monde, ça compte comme une excuse ?"),
    (0, "10:43", "Pepper Potts", "Le monde, ou ta collection de voitures ? 😏"),
    (0, "10:44", "Tony Stark", "Les deux sont liés, c'est scientifique mdr"),
    (0, "10:50", "Pepper Potts", "Mdr. Bon, je t'envoie le compte rendu. Lis-le, vraiment."),
    (1, "19:10", "Tony Stark", "Lu ! Enfin… survolé avec beaucoup d'attention."),
    (1, "19:12", "Pepper Potts", "Survolé avec attention. Évidemment. Tu es un génie de la lecture rapide 🙄"),
    (1, "19:13", "Tony Stark", "Merci, je savais que tu le reconnaîtrais 😎"),
    (1, "21:00", "Pepper Potts", "Tu te prends pour un ministre maintenant ?"),
    (1, "21:02", "Tony Stark", "Exactement, je suis très occupé."),
    (1, "21:03", "Pepper Potts", "mdr"),
    (2, "12:00", "Pepper Potts", "On peut parler du budget du projet Mark 42 ? Les dépenses explosent."),
    (2, "12:30", "Tony Stark", "Explosent comme dans 'beaucoup' ou comme dans 'boum' ?"),
    (2, "12:31", "Pepper Potts", "Tony. Je suis sérieuse cette fois."),
    (2, "12:35", "Tony Stark", "D'accord, d'accord. Envoie-moi les chiffres, je regarde ce soir."),
    (2, "21:00", "Tony Stark", "J'ai regardé. Tu as raison, on doit couper dans les essais."),
    (2, "21:05", "Pepper Potts", "Merci. Vraiment. Ça compte pour moi que tu prennes ça au sérieux."),
    (4, "18:00", "Pepper Potts", "Tu as encore oublié notre dîner hier soir."),
    (4, "18:20", "Tony Stark", "Je suis désolé. Il n'y a pas d'excuse cette fois."),
    (4, "18:45", "Pepper Potts", "Super. Génial. Comme d'habitude."),
    (4, "19:30", "Tony Stark", "Samedi, je réserve le restaurant italien. Promis, je mets trois alarmes."),
    (4, "19:40", "Pepper Potts", "Trois alarmes. On verra bien."),
]


def messages():
    rows = []
    for i, (jour, heure, auteur, texte) in enumerate(ECHANGES):
        h, m = map(int, heure.split(":"))
        quand = (DEBUT + timedelta(days=jour)).replace(hour=h, minute=m)
        rows.append({
            "message_order": i, "source_order": i, "author": auteur, "content": texte,
            "id": f"m{i}", "kind": "text", "media_type": None, "sent_at": quand.isoformat(),
            "sent_at_raw": quand.strftime("%d/%m/%Y %H:%M"),
        })
    return rows


QUESTIONS = [
    "JARVIS, regarde cette discussion et dis-moi ce que tu en penses.",
    "Est-ce qu'elle et moi, on plaisante souvent ?",
    "Qui a écrit « mdr » après la blague sur le ministre ?",
    "Montre-moi les messages où elle me taquine.",
    "Et vers la fin, tu trouves que notre ton a changé ?",
    "Pourquoi tu dis ça ?",
    "Est-ce qu'elle plaisante dans son dernier message ?",
    # Phase 3 : aide à répondre et à relancer.
    "Aide-moi à lui répondre.",
    "Pourquoi tu me proposes la deuxième réponse ?",
    "Je veux reprendre la conversation avec humour.",
]
# QUESTIONS=3,7,8,9,10 : seulement ces questions (numérotées à partir de 1).
import os  # noqa: E402
if os.environ.get("QUESTIONS"):
    QUESTIONS = [QUESTIONS[int(i) - 1] for i in os.environ["QUESTIONS"].split(",")]


async def main():
    settings = get_settings()
    ligne = {
        "id": "ctx-essai", "contact_name": "Pepper Potts", "is_group": False,
        "current_user_name": "Tony Stark", "participants": ["Pepper Potts", "Tony Stark"],
        "period_start": None, "period_end": None, "dates_uncertain": False,
        "created_at": "2026-10-15", "message_id": None, "context_messages": [{"count": len(ECHANGES)}],
    }
    ctx = contexte_joint(ligne, "A")
    ctx.messages = [message_source(ctx, r) for r in messages()]
    moteur = MoteurComprehension(None, None, settings)
    client = get_openai().with_options(max_retries=3)
    historique: list[dict] = []
    systeme = build_system_prompt(Ton.naturel, None, datetime(2026, 10, 15))
    faites = None
    for q in QUESTIONS:
        aide_probable = reperes.analyser(q, [], date(2026, 10, 15)).aide_reponse
        extra = settings.comprehension_extra_output_tokens if aide_probable else 0
        p = moteur.preparer(systeme=systeme, contextes=[ctx], cibles=[ctx], historique=historique,
                            question=q, aujourd_hui=date(2026, 10, 15),
                            budget=settings.comprehension_budget_tokens - extra,
                            propositions_faites=faites)
        debut = time.time()
        r = await client.chat.completions.create(
            model=settings.openai_model, messages=p.messages,
            max_tokens=settings.comprehension_max_output_tokens + extra,
        )
        brut = r.choices[0].message.content or ""
        c = CorrecteurAttributions(p.fournis)
        f = FiltreReperes(c)
        b = aide.FiltrePropositions()
        texte = f.ajouter(b.ajouter(brut) + b.terminer()) + f.terminer()
        v = verifier(texte, f.reperes, p.fournis)
        v.corrigees, v.ecartees = c.corrigees, c.ecartees
        props = None
        if b.bloc:
            # Génération par lots (correction finale 5.1), comme la route de chat.
            ens = generation.annoncer(b.bloc, p.fournis, ctx.id)
            debut_lots = time.time()
            if not ens.complet:
                lots = get_openai().with_options(max_retries=0)
                async for _ in completer_ensemble(ens, ctx, question=q, analyse=texte,
                                                  aujourd_hui=date(2026, 10, 15), memoire_bloc=None,
                                                  client=lots, settings=settings):
                    pass
            entree = ens.stockage()
            props = aide.lues([entree], "essai")
            print(f"   LOTS : {ens.requetes} requête(s), {ens.tokens_entree} + {ens.tokens_sortie} tokens, "
                  f"{time.time() - debut_lots:.1f} s, statut={entree['statut']}, raison={ens.raison}, "
                  f"tons annoncés={ens.tons}, manquantes={ens.nombre_manquant()}")
            for t in entree["tons"]:
                for lo in generation.LONGUEURS:
                    xs = [x for x in t["propositions"] if x["longueur"] == lo]
                    print(f"   [{t['nom']} · {lo}] {len(xs)}")
                    for x in xs:
                        print(f"     {x['rang']}. ({x['approche']}) {x['texte']}")
        if props and props.get("tons"):
            faites = props
        print(f"\n### {q}\n({r.usage.prompt_tokens} tokens envoyés, estimés {p.tokens_estimes}, "
              f"{r.usage.completion_tokens} produits, {time.time() - debut:.1f} s)\n"
              f"BRUT : {brut}\nVISIBLE : {texte}")
        for ref in v.references:
            print(f"   ↳ {ref['author']} · {ref['date_label']} · « {ref['excerpt']} »")
        print(f"   corrigées={v.corrigees} écartées={v.ecartees} "
              f"refusées={v.refusees} contredites={v.attributions_contredites} "
              f"introuvables={v.citations_introuvables} note={v.note}")
        historique += [{"role": "user", "content": q}, {"role": "assistant", "content": texte}]
        await asyncio.sleep(20)   # limite de 8 000 tokens par minute


asyncio.run(main())
