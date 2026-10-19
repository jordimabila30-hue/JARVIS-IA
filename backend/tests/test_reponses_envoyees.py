"""Phase 3 finale (identifiants, justification) et phase 4 (réponses
déclarées envoyées, mémoire du contact). IA simulée, Supabase simulée."""

import time

import jwt

from app.comprehension import propositions as aide
from app.comprehension.attribution import CorrecteurAttributions
from app.comprehension.references import FiltreReperes
from app.config import get_settings

from test_chat import auth_headers
from test_comprehension import AUTRE, CHAT, CTX_PEPPER
from test_propositions import BLOC_COMPLET as BLOC
from test_references import env, evenements, moquerie, post, preparer, reponse  # noqa: F401

settings = get_settings()


def entetes(user):
    token = jwt.encode({"sub": user, "role": "authenticated", "aud": "authenticated",
                        "iss": settings.supabase_issuer, "exp": int(time.time()) + 3600},
                       settings.supabase_jwt_secret, algorithm="HS256")
    return {"Authorization": f"Bearer {token}"}


async def proposer(env):
    """Une réponse avec propositions (Taquin, Naturel, Sérieux) ; renvoie
    (id de la réponse, propositions enregistrées)."""
    env.llm = reponse("Voici des idées.\n" + BLOC)
    await post(env, message="Aide-moi à lui répondre", conversation_id=CHAT, whatsapp_analysis="allowed")
    ligne = [r for r in env.supa.inserted if r["role"] == "assistant"][-1]
    return ligne["id"], aide.lues(ligne["attachments"], ligne["id"])


def route(message_id, proposition_id):
    return f"/api/v1/conversations/{CHAT}/messages/{message_id}/propositions/{proposition_id}/envoyee"


# --- Phase 3 : identifiants ---------------------------------------------------

async def test_identifiants_uniques_stables_et_restaures(env):
    mid, p = await proposer(env)
    ids = [x["id"] for t in p["tons"] for x in t["propositions"]]
    assert len(ids) == 36 == len(set(ids))
    resp = await env.client.get(f"/api/v1/conversations/{CHAT}/references", headers=auth_headers())
    restaurees = resp.json()["items"][0]["propositions"]
    assert [x["id"] for t in restaurees["tons"] for x in t["propositions"]] == ids
    assert all(x["envoyee"] is None for t in restaurees["tons"] for x in t["propositions"])


def test_anciennes_propositions_sans_identifiant():
    ancienne = [{"type": aide.TYPE, "mode": "reponse", "tons": [
        {"nom": "Amical", "propositions": [{"texte": f"Message {i}", "appuis": []} for i in range(3)]}]}]
    a = aide.lues(ancienne, "msg-1")
    b = aide.lues(ancienne, "msg-1")
    ids = [x["id"] for x in a["tons"][0]["propositions"]]
    assert ids == [x["id"] for x in b["tons"][0]["propositions"]] and len(set(ids)) == 3
    assert ids != [x["id"] for x in aide.lues(ancienne, "msg-2")["tons"][0]["propositions"]]


async def test_pourquoi_la_deuxieme_reference_explicite(env):
    mid, p = await proposer(env)
    naturel_2 = p["tons"][1]["propositions"][1]
    env.llm = reponse("Je t'ai proposé « Je suis là dans 10 minutes, promis. » pour la rassurer.")
    await post(env, message="Pourquoi la deuxième ?", conversation_id=CHAT, whatsapp_analysis="allowed",
               ton_propose="Naturel", longueur_proposee="court", propositions_message_id=mid)
    rappel = env.llm.calls[0]["messages"][-2]["content"]
    assert f"PROPOSITION VISÉE (identifiant {naturel_2['id']}) : ton « Naturel », longueur « Court », n° 2" in rappel
    assert "«Je suis là dans 10 minutes, promis.»" in rappel


async def test_reference_d_un_autre_chat_ignoree(env):
    await proposer(env)
    env.llm = reponse("Parce que.")
    resp = await post(env, message="Pourquoi la deuxième ?", conversation_id=CHAT, whatsapp_analysis="allowed",
                      propositions_message_id="77777777-7777-7777-7777-777777777777")
    assert resp.status_code == 200     # rien d'exposé ; repli sur les propositions du chat


def test_proposition_inventee_retablie_mot_pour_mot():
    _, p = preparer(moquerie())
    props = ["Désolé pour le retard, j'arrive !", "Je suis là dans 10 minutes, promis.",
             "Tu veux que je ramène quelque chose ?"]
    c = CorrecteurAttributions(p.fournis, propositions=props, visee=props[1])
    f = FiltreReperes(c)
    texte = ("La deuxième proposition était « Tu as encore un peu d'énergie ce soir ? ». "
             "Elle rassure Pepper.")
    visible = f.ajouter(texte) + f.terminer()
    assert visible == ("La deuxième proposition était « Je suis là dans 10 minutes, promis. ». "
                       "Elle rassure Pepper.")
    assert c.propositions_retablies == 1
    # Une citation exacte, ou d'un message WhatsApp, est laissée telle quelle.
    c2 = CorrecteurAttributions(p.fournis, propositions=props, visee=props[1])
    f2 = FiltreReperes(c2)
    t2 = "Ta proposition « Je suis là dans 10 minutes, promis. » répond à « Tu te prends pour un ministre maintenant ? »."
    assert f2.ajouter(t2) + f2.terminer() == t2 and c2.propositions_retablies == 0


# --- Phase 4 : déclarer, annuler, isoler --------------------------------------

async def test_declarer_idempotent_annuler_redeclarer(env):
    mid, p = await proposer(env)
    pid = p["tons"][1]["propositions"][0]["id"]
    r1 = await env.client.put(route(mid, pid), headers=auth_headers())
    assert r1.status_code == 200 and r1.json()["envoyee"] and r1.json()["declared_at"]
    r2 = await env.client.put(route(mid, pid), headers=auth_headers())      # double appui
    assert r2.json() == r1.json()
    ligne = next(r for r in env.supa.inserted if r["id"] == mid)
    [d] = aide.declarations(ligne["attachments"])
    assert d["statut"] == "declaree_envoyee" and d["texte"] == "Désolé pour le retard, j'arrive !"
    assert d["ton"] == "Naturel" and d["contact"] == "Pepper Potts" and d["conversation_id"] == CHAT
    assert d["context_id"] == CTX_PEPPER and d["proposition_id"] == pid
    # Jamais un faux message WhatsApp original.
    assert all(m["content"] != d["texte"] for m in env.supa.context_messages[CTX_PEPPER])
    # Restauration : statut renvoyé avec la proposition.
    items = (await env.client.get(f"/api/v1/conversations/{CHAT}/references", headers=auth_headers())).json()
    statut = {x["id"]: x["envoyee"] for t in items["items"][0]["propositions"]["tons"] for x in t["propositions"]}
    assert statut[pid] == d["declared_at"] and sum(1 for v in statut.values() if v) == 1
    # Annulation : gardée, reflétée.
    r3 = await env.client.delete(route(mid, pid), headers=auth_headers())
    assert r3.json()["envoyee"] is False and r3.json()["cancelled_at"]
    [d] = aide.declarations(next(r for r in env.supa.inserted if r["id"] == mid)["attachments"])
    assert d["statut"] == "annulee"
    items = (await env.client.get(f"/api/v1/conversations/{CHAT}/references", headers=auth_headers())).json()
    assert all(x["envoyee"] is None for t in items["items"][0]["propositions"]["tons"] for x in t["propositions"])
    # Redéclarer : une seule entrée, de nouveau active.
    await env.client.put(route(mid, pid), headers=auth_headers())
    assert len(aide.declarations(next(r for r in env.supa.inserted if r["id"] == mid)["attachments"])) == 1


async def test_isolation_entre_comptes_et_identifiant_inconnu(env):
    mid, p = await proposer(env)
    pid = p["tons"][0]["propositions"][0]["id"]
    assert (await env.client.put(route(mid, pid), headers=entetes(AUTRE))).status_code == 404
    assert (await env.client.put(route(mid, "12345678-1234-1234-1234-123456789012"),
                                 headers=auth_headers())).status_code == 404
    assert (await env.client.put(route(mid, pid), headers={})).status_code in (401, 403)
    assert not aide.declarations(next(r for r in env.supa.inserted if r["id"] == mid)["attachments"])


# --- Mémoire : réutilisée plus tard ------------------------------------------

async def test_memoire_redonnee_au_modele_pour_ce_contact(env):
    mid, p = await proposer(env)
    pid = p["tons"][1]["propositions"][1]["id"]
    await env.client.put(route(mid, pid), headers=auth_headers())
    env.llm = reponse("Voici d'autres idées.\n" + BLOC)
    await post(env, message="Aide-moi encore à lui répondre", conversation_id=CHAT, whatsapp_analysis="allowed")
    rappel = env.llm.calls[0]["messages"][-2]["content"]
    assert "<reponses_declarees_envoyees>" in rappel
    assert "« Pepper Potts »" in rappel and "ton « Naturel » : «Je suis là dans 10 minutes, promis.»" in rappel
    assert "non vérifié dans WhatsApp" in rappel and "pas une préférence permanente" in rappel
    assert "dans l'export" not in rappel
    # Une fois annulée, elle n'est plus redonnée.
    await env.client.delete(route(mid, pid), headers=auth_headers())
    env.llm = reponse("Encore.")
    await post(env, message="Et maintenant ?", conversation_id=CHAT, whatsapp_analysis="allowed")
    assert "<reponses_declarees_envoyees>" not in env.llm.calls[0]["messages"][-2]["content"]


async def test_reponse_retrouvee_dans_un_nouvel_export_pas_comptee_deux_fois(env):
    mid, p = await proposer(env)
    pid = p["tons"][0]["propositions"][1]["id"]
    texte = p["tons"][0]["propositions"][1]["texte"]
    await env.client.put(route(mid, pid), headers=auth_headers())
    # Le nouvel export contient ce message, écrit par l'utilisateur (Tony).
    env.supa.context_messages[CTX_PEPPER][-1] = {**env.supa.context_messages[CTX_PEPPER][-1],
                                                  "author": "Tony Stark", "content": texte}
    await env.redis.flushdb()
    env.llm = reponse("Ok.")
    await post(env, message="Que lui dire maintenant ?", conversation_id=CHAT, whatsapp_analysis="allowed")
    assert "ne la compte pas deux fois" in env.llm.calls[0]["messages"][-2]["content"]


async def test_chat_sans_propositions_inchange(env):
    env.llm = reponse("Pepper répond « mdr » [[3]].")
    resp = await post(env, message="Qui rit ? Montre-moi.", conversation_id=CHAT, whatsapp_analysis="allowed")
    ev = evenements(resp.text)
    assert [r["author"] for r in next(d for e, d in ev if e == "references")["references"]] == ["Pepper Potts"]
    assert all(m["role"] != "system" for m in env.llm.calls[0]["messages"][1:])


async def test_preflight_cors_du_web_pour_declarer_et_annuler():
    """Campagne de tests : le Web (Flutter, port 3000) échouait en
    « Non enregistrée » — PUT absent des méthodes CORS autorisées."""
    import httpx
    from app.main import app as application
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=application),
                                 base_url="http://test") as client:
        for methode in ("PUT", "DELETE"):
            r = await client.options(
                route("m", "p"),
                headers={"Origin": "http://localhost:3000", "Access-Control-Request-Method": methode,
                         "Access-Control-Request-Headers": "authorization"})
            assert r.status_code == 200, methode
            assert methode in r.headers["access-control-allow-methods"]
