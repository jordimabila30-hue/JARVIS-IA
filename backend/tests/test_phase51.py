"""Phase 5.1 : tons × longueurs (court / moyen / long), Professionnel,
toutes les combinaisons préparées d'un coup, un seul choix « envoyée » par
ensemble. IA simulée, Supabase simulée (fonctions SQL testées en local :
supabase/tests/40_reponse_envoyee_unique_test.sql)."""

from app.comprehension import propositions as aide
from app.comprehension.propositions import analyser

from test_chat import auth_headers
from test_comprehension import CHAT
from test_references import env, evenements, moquerie, post, preparer, reponse  # noqa: F401

TEXTES = {
    "court": ["J'arrive !", "Dix minutes, promis.", "Tu veux un café ?"],
    "moyen": ["Désolé, j'arrive. Garde-moi une place.", "Je suis là dans dix minutes. Promis, cette fois c'est vrai.",
              "Tu veux que je ramène quelque chose ? Je passe devant la boulangerie."],
    "long": ["Je suis vraiment désolé pour le retard. La réunion a débordé. J'arrive le plus vite possible. "
             "Garde-moi une place.",
             "Dix minutes et je suis là. J'ai pris le métro. Je t'envoie un message en sortant. On commence sans moi ?",
             "Tu veux un café ? Je passe devant ton endroit préféré. Dis-moi lequel. Je t'invite pour me faire pardonner."],
}


def bloc(tons=("Naturel", "Amical", "Taquin", "Professionnel"), sauf=None, mode="reponse"):
    lignes = [f'<propositions mode="{mode}">']
    for t in tons:
        lignes.append(f"Ton : {t}")
        for lo, nom in (("court", "Court"), ("moyen", "Moyen"), ("long", "Long")):
            if sauf == (t, lo):
                continue
            lignes.append(f"{nom} :")
            lignes += [f"{i}. [approche {i}] {texte} ({t})" for i, texte in enumerate(TEXTES[lo], 1)]
    lignes.append("</propositions>")
    return "\n".join(lignes)


def test_toutes_les_combinaisons_avec_professionnel():
    _, p = preparer(moquerie())
    r = analyser(bloc(), p.fournis, None)
    assert [t["nom"] for t in r["tons"]] == ["Naturel", "Amical", "Taquin", "Professionnel"]
    assert r["longueurs"] == ["court", "moyen", "long"]
    for t in r["tons"]:
        assert len(t["propositions"]) == 9
        for lo in ("court", "moyen", "long"):
            trois = [x for x in t["propositions"] if x["longueur"] == lo]
            assert [x["rang"] for x in trois] == [1, 2, 3]
            assert len({x["texte"] for x in trois}) == 3
    ids = [x["id"] for t in r["tons"] for x in t["propositions"]]
    assert len(ids) == 36 == len(set(ids))


def test_combinaison_incomplete_signalee_jamais_retiree_en_silence():
    _, p = preparer(moquerie())
    r = analyser(bloc(sauf=("Taquin", "long")), p.fournis, None)
    assert [t["nom"] for t in r["tons"]] == ["Naturel", "Amical", "Professionnel"]
    assert r["incomplets"] == ["Taquin"]


def test_forme_crochets_ton_et_longueur():
    _, p = preparer(moquerie())
    lignes = ['<propositions mode="relance">']
    for lo in ("Court", "Moyen", "Long"):
        lignes += [f"[Professionnel · {lo}] {i}. {t}" for i, t in enumerate(TEXTES[lo.lower()], 1)]
    lignes.append("</propositions>")
    r = analyser("\n".join(lignes), p.fournis, None)
    assert [t["nom"] for t in r["tons"]] == ["Professionnel"] and len(r["tons"][0]["propositions"]) == 9


def test_anciennes_propositions_sans_longueur():
    ancienne = [{"type": aide.TYPE, "mode": "reponse", "tons": [
        {"nom": "Amical", "propositions": [{"texte": f"Message {i}", "appuis": []} for i in range(3)]}]}]
    p = aide.lues(ancienne, "msg-1")
    assert p["longueurs"] == [] and p["ensemble"] == "msg-1"
    assert [(x["longueur"], x["rang"]) for x in p["tons"][0]["propositions"]] == [(None, 1), (None, 2), (None, 3)]
    assert aide.visee(p, "Amical", "pourquoi la deuxième ?", "long")[2]["texte"] == "Message 1"


async def generer(env):
    env.llm = reponse("Voici des idées.\n" + bloc())
    await post(env, message="Aide-moi à lui répondre", conversation_id=CHAT, whatsapp_analysis="allowed")
    ligne = [r for r in env.supa.inserted if r["role"] == "assistant"][-1]
    return ligne, aide.lues(ligne["attachments"], ligne["id"])


async def test_bloc_deja_complet_aucun_lot_et_restaure(env):
    # Le modèle a tout écrit correctement dans la réponse principale : rien
    # à compléter, aucune requête de plus.
    ligne, p = await generer(env)
    assert len(env.llm.calls) == 1
    appel = env.llm.calls[0]
    assert appel["max_tokens"] == 1500           # la réponse principale n'écrit plus les messages
    assert "Professionnel" in appel["messages"][0]["content"]
    assert p["statut"] == "complet"
    items = (await env.client.get(f"/api/v1/conversations/{CHAT}/references", headers=auth_headers())).json()["items"]
    restaurees = items[0]["propositions"]
    assert restaurees["longueurs"] == ["court", "moyen", "long"] and restaurees["ensemble"] == ligne["id"]
    assert sum(len(t["propositions"]) for t in restaurees["tons"]) == 36


async def test_pourquoi_la_deuxieme_selon_ton_et_longueur(env):
    ligne, p = await generer(env)
    pro = next(t for t in p["tons"] if t["nom"] == "Professionnel")
    vise = next(x for x in pro["propositions"] if x["longueur"] == "long" and x["rang"] == 2)
    env.llm = reponse("Parce que.")
    await post(env, message="Pourquoi la deuxième ?", conversation_id=CHAT, whatsapp_analysis="allowed",
               ton_propose="Professionnel", longueur_proposee="long", propositions_message_id=ligne["id"])
    rappel = env.llm.calls[0]["messages"][-2]["content"]
    assert f"PROPOSITION VISÉE (identifiant {vise['id']}) : ton « Professionnel », longueur « Long », n° 2" in rappel
    assert "Affichés à l'écran (ton « Professionnel », longueur « Long »" in rappel


async def test_un_seul_choix_par_ensemble_tous_tons_et_longueurs(env):
    ligne, p = await generer(env)
    base = f"/api/v1/conversations/{CHAT}/messages/{ligne['id']}/propositions"
    amical_moyen_2 = next(x for x in p["tons"][1]["propositions"] if x["longueur"] == "moyen" and x["rang"] == 2)
    pro_court_1 = next(x for x in p["tons"][3]["propositions"] if x["longueur"] == "court" and x["rang"] == 1)
    r = await env.client.put(f"{base}/{amical_moyen_2['id']}/envoyee", headers=auth_headers())
    assert r.status_code == 200 and r.json()["envoyee"]
    # Même proposition : idempotent ; une autre (autre ton, autre longueur) : refusée.
    assert (await env.client.put(f"{base}/{amical_moyen_2['id']}/envoyee", headers=auth_headers())).status_code == 200
    r = await env.client.put(f"{base}/{pro_court_1['id']}/envoyee", headers=auth_headers())
    assert r.status_code == 409 and r.json()["detail"] == {
        "code": "deja_choisi", "proposition_id": amical_moyen_2["id"],
        "message": "Une autre proposition de cet ensemble est déjà choisie."}
    actives = [d for d in aide.declarations(ligne["attachments"]) if d["statut"] == "declaree_envoyee"]
    assert [(d["proposition_id"], d["ton"], d["longueur"], d["rang"]) for d in actives] == [
        (amical_moyen_2["id"], "Amical", "moyen", 2)]
    # Annulé : l'ensemble redevient disponible.
    await env.client.delete(f"{base}/{amical_moyen_2['id']}/envoyee", headers=auth_headers())
    r = await env.client.put(f"{base}/{pro_court_1['id']}/envoyee", headers=auth_headers())
    assert r.status_code == 200
    # Un nouvel ensemble est indépendant.
    ligne2, p2 = await generer(env)
    autre = p2["tons"][0]["propositions"][0]
    r = await env.client.put(f"/api/v1/conversations/{CHAT}/messages/{ligne2['id']}/propositions/{autre['id']}/envoyee",
                             headers=auth_headers())
    assert r.status_code == 200


async def test_flux_inchange_texte_principal_diffuse(env):
    env.llm = reponse("Lina attend ta réponse. Voici des idées.\n", bloc()[:400], bloc()[400:])
    resp = await post(env, message="Que lui dire ?", conversation_id=CHAT, whatsapp_analysis="allowed")
    ev = evenements(resp.text)
    assert "".join(d["text"] for e, d in ev if e == "delta") == "Lina attend ta réponse. Voici des idées."
    props = next(d for e, d in ev if e == "propositions")
    assert props["longueurs"] == ["court", "moyen", "long"] and len(props["tons"]) == 4

