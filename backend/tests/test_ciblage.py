"""Ciblage déterministe du message visé (« sa dernière réponse »…), vérifié
AVANT tout appel à l'IA, sur les conversations fictives de tests_whatsapp/.

Lancer depuis la racine du dépôt monté (les ZIP sont hors de backend/)."""

from app.comprehension import ciblage
from app.comprehension.moteur import message_source

from test_campagne import contexte, preparer
from test_comprehension import CHAT
from test_references import env, post, reponse  # noqa: F401

LINA = "JARVIS_TEST_SENTIMENTAL.zip"
GROUPE = "JARVIS_TEST_GROUPE.zip"
SAMUEL = "JARVIS_TEST_AMITIE.zip"


def ajouter(ctx, auteur, texte, origine):
    """Ajout manuel tel qu'enregistré : rang suivant, AUCUNE date."""
    ordre = ctx.messages[-1].ordre + 1
    ctx.messages.append(message_source(ctx, {
        "id": f"manuel-{ordre}", "message_order": ordre, "source_order": None, "author": auteur,
        "content": texte, "kind": "text", "sent_at": None, "sent_at_raw": "", "origin": origine}))
    return ctx.messages[-1]


def vise(question, contextes, precedentes=None):
    c = ciblage.cibler(question, contextes, precedentes)
    assert c is not None and c.cible is not None, c
    return c.cible


def test_dernier_message_de_lina_ajoute_a_la_main_devance_l_export_date():
    ctx = contexte(LINA)
    dernier_date = ctx.messages[-1]
    m = ajouter(ctx, "Lina Moreau", "Bon, je te pardonne pour cette fois.", "manual_received")
    c = vise("JARVIS, que penses-tu de la dernière réponse de Lina ?", [ctx])
    assert c.message is m and c.message is not dernier_date
    assert c.genre == "participant" and c.participant == "Lina Moreau"
    # Sans nom, discussion à deux : le contact.
    assert vise("Que penses-tu de sa dernière réponse ?", [ctx]).message is m
    assert vise("Et son dernier message ?", [ctx]).message is m


def test_dernier_message_d_alex_et_dernier_envoye():
    ctx = contexte(LINA)
    ajouter(ctx, "Lina Moreau", "Tu viens samedi ?", "manual_received")
    m = ajouter(ctx, "Alex Martin", "Oui, avec plaisir !", "manual_sent")
    ajouter(ctx, "Lina Moreau", "Super !", "manual_received")
    assert vise("Que penses-tu de mon dernier message ?", [ctx]).message is m
    assert vise("Le dernier message d'Alex est-il clair ?", [ctx]).message is m
    assert vise("Et le dernier message que j'ai envoyé ?", [ctx]).message is m
    assert vise("Et le dernier message reçu ?", [ctx]).message.contenu == "Super !"
    assert vise("Le dernier ajout manuel ?", [ctx]).message.contenu == "Super !"


def test_groupe_derniere_reponse_de_samuel_alors_que_nora_a_parle_ensuite():
    ctx = contexte(GROUPE)
    s = ajouter(ctx, "Samuel Petit", "Je m'occupe du rapport.", "manual_received")
    n = ajouter(ctx, "Nora Laurent", "Merci Samuel !", "manual_received")
    c = vise("Que penses-tu de la dernière réponse de Samuel ?", [ctx])
    assert c.message is s and c.participant == "Samuel Petit"
    # Le groupe : le tout dernier, quel que soit l'auteur.
    assert vise("Que dit le dernier message du groupe ?", [ctx]).message is n
    # Groupe, aucun nom : jamais de supposition.
    amb = ciblage.cibler("Que penses-tu de sa dernière réponse ?", [ctx])
    assert amb.cible is None and "Samuel Petit" in amb.ambigus and "Nora Laurent" in amb.ambigus
    # Suivi : la personne de la question précédente.
    assert vise("Et sa dernière réponse ?", [ctx], ["Qu'a dit Samuel sur le budget ?"]).message is s


def test_plusieurs_ajouts_sans_date_et_messages_identiques():
    ctx = contexte(LINA)
    ajouter(ctx, "Lina Moreau", "ok", "manual_received")
    ajouter(ctx, "Alex Martin", "Tu es sûre ?", "manual_sent")
    deuxieme = ajouter(ctx, "Lina Moreau", "ok", "manual_received")
    c = vise("Que penses-tu de sa dernière réponse ?", [ctx])
    assert c.message is deuxieme and c.message.id == deuxieme.id      # le plus récent des deux « ok »


def test_plusieurs_contextes_dans_le_meme_chat():
    lina = contexte(LINA, "A", "aaaaaaaa-0000-0000-0000-00000000000a")
    samuel = contexte(SAMUEL, "B", "aaaaaaaa-0000-0000-0000-00000000000b")
    m = ajouter(samuel, "Samuel Petit", "Partant pour dimanche !", "manual_received")
    assert vise("Que penses-tu de la dernière réponse de Samuel ?", [lina, samuel]).message is m
    amb = ciblage.cibler("Que penses-tu de sa dernière réponse ?", [lina, samuel])
    assert amb.cible is None and set(amb.ambigus) >= {"Lina Moreau", "Samuel Petit"}
    bloc = ciblage.bloc(amb, {})
    assert "demande en une phrase à l'utilisateur de qui il parle" in bloc


def test_questions_sans_dernier_message_non_ciblees():
    ctx = contexte(LINA)
    assert ciblage.cibler("Pourquoi elle dit ça ?", [ctx]) is None
    assert ciblage.cibler("Résume la discussion", [ctx]) is None


def test_message_vise_toujours_fourni_sous_une_petite_limite_de_tokens():
    ctx = contexte(GROUPE)       # 4 795 messages
    m = ajouter(ctx, "Samuel Petit", "Je m'occupe du rapport.", "manual_received")
    ajouter(ctx, "Nora Laurent", "Merci Samuel !", "manual_received")
    q = "Que penses-tu de la dernière réponse de Samuel ?"
    c = ciblage.cibler(q, [ctx])
    p = preparer_avec(ctx, q, c, budget=2500)
    numeros = {f.message.ordre: n for n, f in p.fournis.items()}
    assert m.ordre in numeros                                   # forcé malgré la limite
    bloc = p.messages[-2]["content"]
    n = numeros[m.ordre]
    assert f"MESSAGE VISÉ (identifiant {m.id}) : [{n}]" in bloc and f"[[{n}]]" in bloc
    assert "Samuel Petit, ajouté à la main" in bloc
    assert "après l'export (date inconnue)" in bloc


def test_anciennes_reponses_erronees_retirees_de_l_historique():
    ctx = contexte(LINA)
    ajouter(ctx, "Lina Moreau", "Bon, je te pardonne pour cette fois.", "manual_received")
    q = "JARVIS, que penses-tu de la dernière réponse de Lina ?"
    historique = [
        {"role": "user", "content": "Résume la discussion"},
        {"role": "assistant", "content": "Vous parlez du traitement du soir."},
        {"role": "user", "content": q},
        {"role": "assistant", "content": "Le dernier message de Lina (« Alors on va devoir continuer le traitement »)…"},
    ]
    p = preparer_avec(ctx, q, ciblage.cibler(q, [ctx], [h["content"] for h in historique if h["role"] == "user"]),
                      historique=historique)
    envoye = [m["content"] for m in p.messages[1:-2]]
    assert "Vous parlez du traitement du soir." in envoye              # le reste du fil est gardé
    assert not any("Alors on va devoir" in t for t in envoye)          # la réponse fausse ne l'ancre plus
    assert "Bon, je te pardonne pour cette fois." in p.messages[-2]["content"]


def preparer_avec(ctx, question, c, budget=None, historique=None):
    from test_campagne import AUJOURDHUI, settings
    from app.comprehension.moteur import MoteurComprehension
    return MoteurComprehension(None, None, settings).preparer(
        systeme="Tu es JARVIS.", contextes=[ctx], cibles=[ctx], historique=historique or [], question=question,
        aujourd_hui=AUJOURDHUI, budget=budget or settings.comprehension_budget_tokens,
        cites=ciblage.voisins(c), ciblage=c)


async def test_route_cible_le_bon_message_avant_l_appel_ia(env):
    # Chat Pepper (fixtures de la route) + ajout manuel : la requête envoyée
    # au fournisseur porte DÉJÀ le message visé, identifié par le serveur.
    rows = env.supa.context_messages[next(iter(env.supa.context_messages))]
    ordre = max(r["message_order"] for r in rows) + 1
    rows.append({"id": "ajout-x", "message_order": ordre, "source_order": None, "author": "Pepper Potts",
                 "content": "Bon, je te pardonne.", "kind": "text", "sent_at": None, "sent_at_raw": "",
                 "origin": "manual_received"})
    env.supa.contexts[0]["context_messages"] = [{"count": len(rows)}]
    env.llm = reponse("Elle te pardonne [[1]].")
    await post(env, message="Que penses-tu de la dernière réponse de Pepper ?", conversation_id=CHAT,
               whatsapp_analysis="allowed")
    appel = env.llm.calls[0]["messages"]
    assert appel[-1]["content"] == "Que penses-tu de la dernière réponse de Pepper ?"
    assert "MESSAGE VISÉ (identifiant ajout-x)" in appel[-2]["content"]
    assert "Bon, je te pardonne." in appel[-2]["content"]
