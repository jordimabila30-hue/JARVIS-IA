"""K1-16 : aide à répondre à un message reçu hors WhatsApp (un seul appel IA)."""

from app.api.v1 import chat
from app.comprehension import aide_libre
from faux_llm import SERVEURS, Scenario
from test_chat import USER
from test_gmail import env, evenements, jeton  # noqa: F401 (fixture)

COMPREHENSION = "Ton amie t'invite à son anniversaire ; tu veux refuser gentiment parce que tu travailles."


VARIANTES = {
    "Court": ["Désolé, je travaille ce soir-là", "Impossible samedi, boulot oblige", "Je ne pourrai pas venir"],
    "Moyen": ["Merci pour l'invitation, mais je travaille samedi soir, profite bien",
              "Ça me touche que tu penses à moi, malheureusement je bosse ce jour-là",
              "J'aurais adoré venir, hélas mon service tombe pile samedi soir"],
    "Long": ["Merci beaucoup de m'inviter, ça me fait vraiment plaisir ; malheureusement je travaille samedi soir",
             "Quelle gentille attention, j'aurais aimé fêter ça avec toi mais mon planning ne me laisse pas libre",
             "Je suis vraiment déçu de rater ta soirée, mon travail m'en empêche ; on se rattrape très vite"],
}


def bloc(tons=("Chaleureux", "Léger", "Professionnel"), par=3) -> str:
    lignes = ['<propositions mode="reponse">']
    for t in tons:
        lignes.append(f"# {t}")
        for lo in ("Court", "Moyen", "Long"):
            lignes.append(lo)
            for i in range(1, par + 1):
                lignes.append(f"{i}. {VARIANTES[lo][i - 1]} ({t.lower()}).")
    lignes.append("</propositions>")
    return "\n".join(lignes)


QUESTION = ("Aide-moi à répondre à ce message que j'ai reçu sur Instagram. Propose une réponse naturelle que je "
            "pourrai copier.\n« Tu viens à mon anniversaire samedi ? »\nEn gros, je voudrais lui dire ceci, "
            "je ne peux pas, je travaille.")


async def _envoyer(env, message, textes):
    serveur = SERVEURS["groq"](Scenario(textes=textes))
    env.llm = serveur.fournisseur()
    r = await env.client.post("/api/v1/chat/stream", json={"message": message}, headers=jeton(USER))
    await chat.wait_background_tasks()
    return serveur, evenements(r.text)


async def test_comprehension_puis_cartes_un_seul_appel(env):
    serveur, ev = await _envoyer(env, QUESTION, [COMPREHENSION + "\n\n", bloc()])
    assert ev[-1][0] == "done"
    assert len(serveur.requetes) == 1                                   # même appel, aucun lot
    assert "AIDE À RÉPONDRE" in str(serveur.requetes[0])
    texte = "".join(d["text"] for e, d in ev if e == "delta")
    assert texte.strip() == COMPREHENSION and "<propositions" not in texte and "bosse" not in texte
    [p] = [d for e, d in ev if e == "propositions"]
    assert [t["nom"] for t in p["tons"]] == ["Chaleureux", "Léger", "Professionnel"]
    assert p["longueurs"] == ["court", "moyen", "long"] and p["statut"] == "complet"
    assert all(len(t["propositions"]) == 9 for t in p["tons"])
    assert len({x["id"] for t in p["tons"] for x in t["propositions"]}) == 27
    [ligne] = [r for r in env.supa.inserted if r["role"] == "assistant"]
    assert ligne["content"].strip() == COMPREHENSION                    # bloc jamais enregistré en texte
    assert ligne["attachments"][0]["type"] == "propositions_reponse"   # 1re pièce : relue par l'appli
    assert ligne["attachments"][0]["context_id"] is None


async def test_question_de_clarification_sans_cartes(env):
    _, ev = await _envoyer(env, "Il m'a écrit, je lui réponds quoi ?", ["Qu'est-ce qu'il t'a écrit exactement ?"])
    assert ev[-1][0] == "done"
    assert not [d for e, d in ev if e == "propositions"]


async def test_bloc_incomplet_jamais_de_cartes_a_moitie(env):
    _, ev = await _envoyer(env, QUESTION, [COMPREHENSION, bloc(par=2)])
    assert not [d for e, d in ev if e == "propositions"]
    assert "bosse" not in "".join(d["text"] for e, d in ev if e == "delta")


async def test_chat_ordinaire_sans_consigne_ni_cartes(env):
    serveur, ev = await _envoyer(env, "Raconte une blague", ["Pourquoi les plongeurs…"])
    assert "AIDE À RÉPONDRE" not in str(serveur.requetes[0])
    assert not [d for e, d in ev if e == "propositions"]


def test_ensemble_ton_incomplet_ecarte():
    e = aide_libre.ensemble(bloc().replace("3. Je ne pourrai pas venir (léger).\n", ""))
    assert [t["nom"] for t in e["tons"]] == ["Chaleureux", "Professionnel"]
