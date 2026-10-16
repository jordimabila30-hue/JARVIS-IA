"""Phase 3 : aide à répondre et à relancer (app/comprehension/propositions.py).

Le modèle est simulé. On vérifie : bloc jamais affiché (même coupé),
exactement trois propositions distinctes par ton, appuis vérifiés,
dernier auteur, enregistrement avec la réponse, restauration, et
« pourquoi la deuxième ? » qui redonne les propositions au modèle.
"""

from datetime import datetime, timedelta

from app.comprehension import extraits, propositions as aide
from app.comprehension.propositions import FiltrePropositions, analyser
from app.config import get_settings

from test_chat import auth_headers
from test_comprehension import CHAT, CTX_PEPPER, msg
from test_references import env, evenements, moquerie, post, preparer, reponse  # noqa: F401

settings = get_settings()

BLOC = """<propositions mode="reponse">
# Taquin
1. [prolonger la blague] Ministre, non. Président, à la rigueur 😏 [[9]]
2. [retourner la pique] Et toi, depuis quand tu comptes mes minutes ?
3. [promettre un geste] OK, j'apporte le café pour me faire pardonner.
# Naturel
1. [s'excuser simplement] Désolé pour le retard, j'arrive !
2. [donner une heure] Je suis là dans 10 minutes, promis.
3. [poser une question] Tu veux que je ramène quelque chose ?
# Sérieux
1. [reconnaître] Tu as raison, je dois être plus ponctuel.
2. [expliquer] J'étais coincé en réunion, désolé.
3. [proposer] La prochaine fois je te préviens avant.
</propositions>"""

# Même contenu au format complet (correction finale 5.1) : les « Court »
# reprennent BLOC (mêmes positions : court n° 1 à 3 en tête de chaque ton),
# Moyen et Long distincts, Professionnel en dernier. Rien à compléter.
_COURTS = {
    "Taquin": ["[prolonger la blague] Ministre, non. Président, à la rigueur 😏 [[9]]",
               "[retourner la pique] Et toi, depuis quand tu comptes mes minutes ?",
               "[promettre un geste] OK, j'apporte le café pour me faire pardonner."],
    "Naturel": ["[s'excuser simplement] Désolé pour le retard, j'arrive !",
                "[donner une heure] Je suis là dans 10 minutes, promis.",
                "[poser une question] Tu veux que je ramène quelque chose ?"],
    "Sérieux": ["[reconnaître] Tu as raison, je dois être plus ponctuel.",
                "[expliquer] J'étais coincé en réunion, désolé.",
                "[proposer] La prochaine fois je te préviens avant."],
    "Professionnel": ["[s'excuser] Je vous prie d'excuser mon retard.",
                      "[préciser] J'arrive d'ici dix minutes.",
                      "[proposer] Souhaitez-vous décaler de quelques minutes ?"],
}


def _moyen(ton, i):
    return f"[idée {i}] {ton} variante {i} alpha{i} beta{i}. Encore gamma{i} delta{i} pour {ton.lower()}{i}."


def _long(ton, i):
    return (f"[idée {i}] {ton} récit{i} un{i} deux{i}. Puis trois{i} quatre{i} cinq{i}. "
            f"Ensuite six{i} sept{i} huit{i}. Enfin neuf{i} dix{i} onze{i} douze{i}.")


BLOC_COMPLET = chr(10).join(
    ['<propositions mode="reponse">']
    + [ligne for ton, courts in _COURTS.items() for ligne in (
        [f"Ton : {ton}", "Court :"] + [f"{i}. {c}" for i, c in enumerate(courts, 1)]
        + ["Moyen :"] + [f"{i}. {_moyen(ton, i)}" for i in (1, 2, 3)]
        + ["Long :"] + [f"{i}. {_long(ton, i)}" for i in (1, 2, 3)])]
    + ["</propositions>"]
)


def test_filtre_cache_le_bloc_meme_coupe():
    brut = "Pepper t'a écrit en dernier. Voici des idées.\n" + BLOC + "\n"
    for pas in (1, 5, 13):
        f = FiltrePropositions()
        visible = "".join(f.ajouter(brut[i:i + pas]) for i in range(0, len(brut), pas)) + f.terminer()
        assert visible == "Pepper t'a écrit en dernier. Voici des idées."
        assert f.ferme and "# Taquin" in f.bloc and "</propositions>" not in f.bloc


def test_texte_apres_le_bloc_garde_ses_espaces():
    f = FiltrePropositions()
    morceaux = ["Idées.\n", BLOC, "\n```\n", "Dis-moi", " laquelle", " te plaît."]
    visible = "".join(f.ajouter(m) for m in morceaux) + f.terminer()
    assert visible == "Idées.\n\nDis-moi laquelle te plaît."


def test_filtre_laisse_les_chevrons_ordinaires():
    f = FiltrePropositions()
    assert f.ajouter("2 < 3 et <b>ok</b>") + f.terminer() == "2 < 3 et <b>ok</b>"
    assert f.bloc is None


def test_analyse_trois_par_ton_et_appuis_verifies():
    _, p = preparer(moquerie())
    r = analyser(BLOC, p.fournis, CTX_PEPPER)
    assert r["mode"] == "reponse" and r["context_id"] == CTX_PEPPER
    assert [t["nom"] for t in r["tons"]] == ["Taquin", "Naturel", "Sérieux"]
    assert all(len(t["propositions"]) == 3 for t in r["tons"])
    premiere = r["tons"][0]["propositions"][0]
    assert premiere["texte"] == "Ministre, non. Président, à la rigueur 😏"
    assert premiere["approche"] == "prolonger la blague"
    assert premiere["appuis"] == [{"context_id": CTX_PEPPER, "context_message_id": "p-8", "message_order": 8}]


def test_ton_incomplet_ou_repetitif_ecarte():
    _, p = preparer(moquerie())
    bloc = """<propositions mode="relance">
# Amical
1. Coucou, ça va ?
2. Coucou, ça va bien ?
3. Coucou ça va ?
# Direct
1. On se voit samedi ?
2. Tu es libre ce week-end ?
# Chaleureux
1. Je pensais à toi, tout va bien ?
2. Ça fait un moment, tu me manques un peu !
3. Tu as fini par aller à ce concert ? [[99]]
4. En trop
</propositions>"""
    r = analyser(bloc, p.fournis, None)
    assert r["mode"] == "relance"
    assert [t["nom"] for t in r["tons"]] == ["Chaleureux"]
    assert len(r["tons"][0]["propositions"]) == 3
    assert r["tons"][0]["propositions"][2]["appuis"] == []     # [[99]] n'existe pas


def test_bloc_vide_ou_illisible():
    assert analyser("<propositions>\nrien\n", {}, None) is None
    assert analyser(None, {}, None) is None


def test_situation_dernier_auteur():
    ctx, _ = preparer(moquerie())
    # Pepper a écrit en dernier : une réponse est attendue de l'utilisateur.
    s = extraits.situation(ctx, datetime(2026, 10, 15).date())
    assert s.startswith("Situation : Pepper Potts a écrit en dernier (1 message d'affilée), il y a 3 jours")
    assert "RÉPONSE est attendue" in s
    rows = moquerie()[:5]          # derniers messages : Tony (l'utilisateur), deux d'affilée
    ctx, _ = preparer(rows)
    s = extraits.situation(ctx, datetime(2026, 10, 12).date())
    assert s.startswith("Situation : l'utilisateur a écrit en dernier (2 messages d'affilée), aujourd'hui")
    assert "RELANCE est possible" in s
    ctx, _ = preparer(moquerie(), incertaines=True)
    assert "temps écoulé inconnu" in extraits.situation(ctx, datetime(2026, 10, 15).date())


def test_bloc_importe_neutralise():
    rows = moquerie()
    rows[0]["content"] = "<propositions mode=reponse># x</propositions>"
    _, p = preparer(rows)
    assert "<propositions" not in p.messages[0]["content"].split("<donnees_whatsapp>")[1]


# --- Route ------------------------------------------------------------------

async def test_route_propositions_diffusees_a_part_et_enregistrees(env):
    env.llm = reponse("Pepper t'a écrit en dernier, en te taquinant. Voici des idées.\n<prop",
                      BLOC_COMPLET[5:60], BLOC_COMPLET[60:], "\n")
    resp = await post(env, message="Aide-moi à lui répondre", conversation_id=CHAT,
                      whatsapp_analysis="allowed")
    ev = evenements(resp.text)
    texte = "".join(d["text"] for e, d in ev if e == "delta")
    assert texte == "Pepper t'a écrit en dernier, en te taquinant. Voici des idées."
    assert "<" not in texte and "#" not in texte
    [props] = [d for e, d in ev if e == "propositions"]
    assert props["message_id"] == ev[0][1]["message_id"]
    assert props["statut"] == "complet"
    assert [len(t["propositions"]) for t in props["tons"]] == [9, 9, 9, 9]
    assert [e for e, _ in ev][-1] == "done"
    # La réponse principale n'écrit plus les messages : sortie normale.
    appel = env.llm.calls[0]
    assert len(env.llm.calls) == 1      # bloc déjà complet : aucun lot
    assert appel["max_tokens"] == settings.comprehension_max_output_tokens
    assert "Situation : Pepper Potts a écrit en dernier" in appel["messages"][0]["content"]
    # Enregistré avec la réponse (même ligne), relu par la restauration.
    [ligne] = [r for r in env.supa.inserted if r["role"] == "assistant"]
    assert ligne["content"] == texte
    stockees = [a for a in ligne["attachments"] if a["type"] == aide.TYPE]
    assert [x["id"] for t in stockees[0]["tons"] for x in t["propositions"]] == [
        x["id"] for t in props["tons"] for x in t["propositions"]]
    resp = await env.client.get(f"/api/v1/conversations/{CHAT}/references", headers=auth_headers())
    [item] = resp.json()["items"]
    assert item["message_id"] == ligne["id"]
    sans_statut = [{**t, "propositions": [{k: v for k, v in x.items() if k != "envoyee"} for x in t["propositions"]]}
                   for t in item["propositions"]["tons"]]
    assert sans_statut == [{**t, "propositions": [{k: v for k, v in x.items() if k != "envoyee"}
                                                   for x in t["propositions"]]} for t in props["tons"]]


async def test_discussion_libre_sans_propositions(env):
    env.llm = reponse("Oui, elle plaisante sans doute [[3]].")
    resp = await post(env, message="Elle plaisante ?", conversation_id=CHAT, whatsapp_analysis="allowed")
    ev = evenements(resp.text)
    assert "propositions" not in [e for e, _ in ev]
    assert env.llm.calls[0]["max_tokens"] == settings.comprehension_max_output_tokens


async def test_bloc_maigre_complete_par_les_lots(env):
    # Une seule proposition écrite par le modèle : jamais affichée à moitié,
    # les lots préparent tout (Naturel + tons de secours + Professionnel).
    env.llm = reponse("Voici des idées.\n<propositions mode=\"reponse\">\n# Naturel\n1. Salut\n</propositions>")
    resp = await post(env, message="Que lui dire ?", conversation_id=CHAT, whatsapp_analysis="allowed")
    ev = evenements(resp.text)
    [props] = [d for e, d in ev if e == "propositions"]
    assert props["statut"] == "complet"
    assert props["tons"][0]["nom"] == "Naturel" and props["tons"][-1]["nom"] == "Professionnel"
    assert all(len(t["propositions"]) == 9 for t in props["tons"])
    assert "".join(d["text"] for e, d in ev if e == "delta") == "Voici des idées."


async def test_bloc_seul_reponse_jamais_vide(env):
    env.llm = reponse(BLOC_COMPLET)
    resp = await post(env, message="Propose-moi une réponse", conversation_id=CHAT, whatsapp_analysis="allowed")
    ev = evenements(resp.text)
    assert "".join(d["text"] for e, d in ev if e == "delta") == "Voici quelques idées de réponse."
    assert "propositions" in [e for e, _ in ev]


async def test_pourquoi_la_deuxieme_redonne_les_propositions(env):
    t = datetime(2026, 1, 1, 8, 0)
    rows = [msg(i, "Pepper Potts" if i % 2 else "Tony Stark", f"message {i}", t + timedelta(hours=i), ctx="q")
            for i in range(3000)]
    rows[1200]["content"] = "Tu viendras au concert ?"
    env.supa.context_messages[CTX_PEPPER] = rows
    env.supa.contexts[0]["context_messages"] = [{"count": 3000}]
    # Les propositions s'appuient sur un message ancien (forcé ensuite).
    env.llm = reponse("Idées.\n<propositions mode=\"relance\">\n# Amical\n"
                      "1. [revenir au concert] Alors, ce concert ? «Tu viendras au concert ?»\n"
                      "2. [nouvelles] Quoi de neuf de ton côté ?\n"
                      "3. [proposer] On se fait un café cette semaine ?\n</propositions>")
    await post(env, message="Comment relancer ?", conversation_id=CHAT, whatsapp_analysis="allowed")
    [ligne] = [r for r in env.supa.inserted if r["role"] == "assistant"]
    [p] = [a for a in ligne["attachments"] if a["type"] == aide.TYPE]
    assert p["statut"] == "complet" and p["tons"][0]["nom"] == "Amical"
    # Proposition affichée par défaut (Moyen, n° 1) ; appui ajouté à la main
    # (comme si le modèle avait cité le message 1200).
    premiere = next(x for x in p["tons"][0]["propositions"] if x["longueur"] == "moyen" and x["rang"] == 1)
    deuxieme = next(x for x in p["tons"][0]["propositions"] if x["longueur"] == "moyen" and x["rang"] == 2)
    premiere["appuis"] = [
        {"context_id": CTX_PEPPER, "context_message_id": "q-1200", "message_order": 1200}]
    env.llm = reponse("Parce qu'elle t'avait posé la question [[1]].")
    await post(env, message="Pourquoi tu me proposes la première ?", conversation_id=CHAT,
               whatsapp_analysis="allowed", ton_propose="Amical")
    messages = env.llm.calls[0]["messages"]
    envoye = messages[0]["content"]
    # Juste avant la question, pas au bout du long message système.
    assert messages[-1] == {"role": "user", "content": "Pourquoi tu me proposes la première ?"}
    assert messages[-2]["role"] == "system"
    bloc = messages[-2]["content"].split("<propositions_precedentes>")[1]
    assert "<propositions_precedentes>" not in envoye
    assert "Affichés à l’écran" not in bloc and f"«{deuxieme['texte']}»" in bloc
    assert "Affichés à l'écran (ton « Amical »" in bloc
    # « la première » : texte exact de la proposition visée, donné au modèle.
    assert f"PROPOSITION VISÉE (identifiant {premiere['id']}) : ton « Amical », longueur « Moyen », n° 1" in bloc
    assert f"«{premiere['texte']}»" in bloc
    # Le message d'appui est fourni de nouveau, et renuméroté pour cette requête.
    assert "«Tu viendras au concert ?»" in envoye
    assert "(appuis : [[" in bloc


def test_guillemets_exterieurs_retires_interieurs_gardes():
    _, p = preparer(moquerie())
    bloc = ("<propositions mode=\"reponse\">\n# Humoristique\n"
            "1. « J'ai une alerte « pepper-alert » qui crie ton nom ! » [[9]]\n"
            "2. \"Trois alarmes, et un café.\"\n"
            "3. [rebondir] « Ministre ? » Non, président.\n</propositions>")
    r = analyser(bloc, p.fournis, None)
    textes = [x["texte"] for x in r["tons"][0]["propositions"]]
    assert textes == ["J'ai une alerte « pepper-alert » qui crie ton nom !",
                      "Trois alarmes, et un café.", "« Ministre ? » Non, président."]


async def test_citer_une_proposition_n_est_pas_une_citation_introuvable(env):
    env.llm = reponse("Idées.\n" + BLOC)
    await post(env, message="Aide-moi à lui répondre", conversation_id=CHAT, whatsapp_analysis="allowed")
    env.llm = reponse("Je te propose « Je suis là dans 10 minutes, promis. » parce que Pepper "
                      "s'impatiente ([[1]]).")
    resp = await post(env, message="Pourquoi la deuxième ?", conversation_id=CHAT,
                      whatsapp_analysis="allowed", ton_propose="Naturel")
    ev = evenements(resp.text)
    texte = "".join(d["text"] for e, d in ev if e == "delta")
    assert "()" not in texte and texte.endswith("s'impatiente.")
    refs = next(d for e, d in ev if e == "references")
    assert [r["context_message_id"] for r in refs["references"]] == ["p-0"]
    assert refs["note"] is None


def test_approche_qui_repete_le_ton_ignoree():
    _, p = preparer(moquerie())
    bloc = ("<propositions mode=\"reponse\">\n# Taquin\n1. [Taquin] Bonne nuit, ne rêve pas trop !\n"
            "2. [prolonger la blague] Dors bien, super-héros.\n3. [taquin] À demain, ministre.\n</propositions>")
    props = analyser(bloc, p.fournis, None)["tons"][0]["propositions"]
    assert [x["approche"] for x in props] == [None, "prolonger la blague", None]


def test_budget_extraits_preserve_pour_l_aide():
    """Instructions estimées à 4 caractères par token : la place des
    messages WhatsApp ne s'effondre pas pour une demande d'aide."""
    t = datetime(2026, 1, 1, 8, 0)
    rows = [msg(i, "Pepper Potts" if i % 2 else "Tony Stark", f"message numéro {i} un peu plus long",
                t + timedelta(minutes=i), ctx="l") for i in range(1000)]
    _, p = preparer(rows, question="Aide-moi à lui répondre",
                    budget=settings.comprehension_budget_tokens - settings.comprehension_extra_output_tokens)
    assert len(p.fournis) >= 30   # place laissée aux lots de propositions, même total par minute
    assert max(f.message.ordre for f in p.fournis.values()) == 999


def test_rang_vise():
    assert aide.rang_vise("Pourquoi tu me proposes la deuxième ?") == 2
    assert aide.rang_vise("pourquoi la deuxieme ?") == 2
    assert aide.rang_vise("Et la 3e, elle sert à quoi ?") == 3
    assert aide.rang_vise("Pourquoi la première réponse ?") == 1
    assert aide.rang_vise("Pourquoi tu dis ça ?") is None
    assert aide.rang_vise("Elle a 2 chats") is None


def test_repere_message_entre_parentheses_retire_entier():
    from app.comprehension.references import FiltreReperes
    f = FiltreReperes()
    visible = f.ajouter("Son dernier message est « Bonne nuit Tony » (message [[9]]). Fin.") + f.terminer()
    assert visible == "Son dernier message est « Bonne nuit Tony ». Fin."
    assert [r.numeros for r in f.reperes] == [[9]]


def test_quota_quotidien_message_honnete_sans_attente():
    import openai
    from app.api.v1 import chat
    from test_comprehension import erreur_api
    exc = erreur_api(openai.RateLimitError, 429, {"retry-after": "632"},
                     {"code": "rate_limit_exceeded"})
    exc.args = ("Rate limit reached ... on tokens per day (TPD): Limit 200000, Used 195297",)
    exc.message = exc.args[0]
    d = chat.describe_llm_error(exc)
    assert d["code"] == "llm_daily_quota"
    assert d["message"].endswith("Réessaie dans environ 11 minutes.")
    assert chat.retry_delay(exc) is None


def test_formes_relachees_du_vrai_modele():
    """Titres de ton sans « # », puces sans numéro."""
    _, p = preparer(moquerie())
    bloc = ("<propositions mode=\"reponse\">\nNaturel :\n- [s'excuser] Désolé, j'arrive tout de suite !\n"
            "- [donner une heure] Je suis là dans dix minutes.\n- [question] Tu veux un café ?\n"
            "**Taquin**\n• [pique] Ministre, non. Président.\n• [blague] Mes minutes valent de l'or.\n"
            "• [promesse] Je t'offre le dessert.\n</propositions>")
    r = analyser(bloc, p.fournis, None)
    assert [t["nom"] for t in r["tons"]] == ["Naturel", "Taquin"]
    assert r["tons"][0]["propositions"][1]["texte"] == "Je suis là dans dix minutes."


def test_forme_sans_contenu():
    assert aide.forme("Naturel :\n1. [x] Bonjour 12") == "a : | 1. [a] a 12"


def test_forme_ton_entre_crochets_du_vrai_modele():
    """Forme réellement produite par GroqCloud (campagne de tests) :
    « [Naturel] 1. message [[30]] », avec ou sans numéro."""
    _, p = preparer(moquerie())
    bloc = ("<propositions mode=\"relance\">\n"
            "[Naturel] 1. Alors, toujours partant pour samedi ? [[3]]\n"
            "[Naturel] 2. J'ai réservé la salle d'escalade, tu viens ?\n"
            "[Naturel] 3. Tu as survécu à ta semaine ?\n"
            "[Taquin] Le canapé t'a encore avalé ?\n"
            "[Taquin] Je commence à croire que tu as peur de la grimpe 😏\n"
            "[Taquin] Dernier appel avant que je grimpe sans toi !\n</propositions>")
    r = analyser(bloc, p.fournis, None)
    assert r["mode"] == "relance"
    assert [t["nom"] for t in r["tons"]] == ["Naturel", "Taquin"]
    assert r["tons"][0]["propositions"][0]["texte"] == "Alors, toujours partant pour samedi ?"
    assert r["tons"][0]["propositions"][0]["appuis"][0]["message_order"] == 2
    # Sous un titre « Ton : … », les crochets restent des approches.
    r = analyser("<propositions>\nTon : Amical\n1. [question] Ça va ?\n2. [envie] On se voit ?\n"
                 "3. [souvenir] Tu te rappelles samedi ?\n</propositions>", p.fournis, None)
    assert [x["approche"] for x in r["tons"][0]["propositions"]] == ["question", "envie", "souvenir"]
