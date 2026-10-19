"""Phase 5 : actualisation manuelle d'un contexte WhatsApp (copier-coller).
IA simulée, Supabase simulée (la fonction SQL est testée en PostgreSQL
local : supabase/tests/30_ajouts_manuels_test.sql)."""

import time
from types import SimpleNamespace
from uuid import uuid4

import httpx
import jwt
import pytest_asyncio
from fastapi import FastAPI

from app.api.v1 import chat, contexts
from app.comprehension import propositions as aide
from app.comprehension.moteur import cle_cache
from app.config import get_settings
from app.quota import QuotaService, get_quota_service
from app.redis_client import get_redis
from app.supabase_client import get_supabase

from test_chat import auth_headers, fournisseur_test
from test_comprehension import AUTRE, CHAT, CTX_PEPPER, FakeSupabase, ctx_row, pepper
from test_propositions import BLOC_COMPLET as BLOC
from test_references import evenements, reponse

settings = get_settings()


def entetes(user):
    token = jwt.encode({"sub": user, "role": "authenticated", "aud": "authenticated",
                        "iss": settings.supabase_issuer, "exp": int(time.time()) + 3600},
                       settings.supabase_jwt_secret, algorithm="HS256")
    return {"Authorization": f"Bearer {token}"}


@pytest_asyncio.fixture
async def env(redis):
    supa = FakeSupabase()
    service = QuotaService(redis, supa)
    app = FastAPI()
    app.include_router(chat.router, prefix="/api/v1")
    app.include_router(contexts.conversations_router, prefix="/api/v1")
    app.include_router(contexts.contexts_router, prefix="/api/v1")
    app.dependency_overrides[get_quota_service] = lambda: service
    app.dependency_overrides[get_supabase] = lambda: supa
    app.dependency_overrides[get_redis] = lambda: redis
    app.dependency_overrides[chat.get_fournisseur] = lambda: fournisseur_test(e.llm)
    client = httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test")
    e = SimpleNamespace(client=client, supa=supa, redis=redis, llm=reponse("Rien."))
    yield e
    await client.aclose()


def message(direction, texte, auteur=None, **extra):
    return {"id": str(uuid4()), "direction": direction, "content": texte,
            **({"author": auteur} if auteur else {}), **extra}


async def ajouter(env, *messages, ctx=CTX_PEPPER, confirmer=False, headers=None):
    return await env.client.post(f"/api/v1/contexts/{ctx}/messages",
                                 json={"messages": list(messages), "confirm_duplicates": confirmer},
                                 headers=headers or auth_headers())


def manuels(env, ctx=CTX_PEPPER):
    return [r for r in env.supa.context_messages[ctx] if r.get("origin", "export") != "export"]


# --- Ajout : reçu, envoyé, plusieurs, auteurs, dates, ordre --------------------

async def test_recu_puis_envoye_dans_l_ordre_sans_appel_ia(env):
    n = len(pepper())
    r = await ajouter(env, message("received", "Ah bon ? Et tu comptais me le dire quand ?"),
                      message("sent", "Finalement je serai disponible samedi.",
                              sent_at="2026-10-16T09:12:00", sent_at_raw="16/10/2026 09:12"))
    assert r.status_code == 201
    lignes = r.json()["messages"]
    assert [(l["message_order"], l["origin"], l["author"]) for l in lignes] == [
        (n, "manual_received", "Pepper Potts"), (n + 1, "manual_sent", "Tony Stark")]
    assert lignes[0]["sent_at"] is None and lignes[0]["sent_at_raw"] == ""    # rien d'inventé
    assert lignes[1]["sent_at"] == "2026-10-16T09:12:00"
    assert env.llm.calls == []                                               # aucun appel IA
    # Les messages d'export n'ont pas bougé.
    assert [r["content"] for r in env.supa.context_messages[CTX_PEPPER][:n]] == [r["content"] for r in pepper()]


async def test_reessai_idempotent(env):
    m = message("received", "Tu es là ?")
    await ajouter(env, m)
    await ajouter(env, m)
    assert len(manuels(env)) == 1


async def test_auteurs_verifies_jamais_devines(env):
    # Reçu : jamais l'utilisateur, jamais un inconnu.
    r = await ajouter(env, message("received", "Coucou", auteur="Tony Stark"))
    assert r.status_code == 422 and r.json()["detail"]["code"] == "auteur_invalide"
    r = await ajouter(env, message("received", "Coucou", auteur="Natasha"))
    assert r.status_code == 422
    # Envoyé sans « Vous êtes » confirmé : refusé.
    env.supa.contexts[0]["current_user_name"] = None
    r = await ajouter(env, message("sent", "Salut"))
    assert r.status_code == 422 and "qui vous êtes" in r.json()["detail"]["message"]
    assert manuels(env) == []


async def test_groupe_auteur_obligatoire_parmi_les_participants(env):
    env.supa.contexts[0].update({"is_group": True, "contact_name": "Projet Nova",
                                 "participants": ["Tony Stark", "Pepper Potts", "Rhodey"]})
    assert (await ajouter(env, message("received", "oui"))).status_code == 422
    r = await ajouter(env, message("received", "oui", auteur="Rhodey"),
                      message("received", "d'accord", auteur="Pepper Potts"))
    assert [l["author"] for l in r.json()["messages"]] == ["Rhodey", "Pepper Potts"]


async def test_tout_ou_rien_si_un_auteur_est_invalide(env):
    r = await ajouter(env, message("received", "Valide"), message("received", "Intrus", auteur="Natasha"))
    assert r.status_code == 422 and manuels(env) == []


# --- Doublons ------------------------------------------------------------------

async def test_doublon_d_un_message_existant_signale_puis_confirme(env):
    dernier = [m for m in pepper() if m["author"] == "Pepper Potts"][-1]
    r = await ajouter(env, message("received", dernier["content"]))
    assert r.status_code == 409
    [c] = r.json()["detail"]["items"]
    assert c["type"] == "message" and c["message_order"] == dernier["message_order"] and c["origin"] == "export"
    assert manuels(env) == []          # rien n'est écrit sans confirmation
    r = await ajouter(env, message("received", dernier["content"]), confirmer=True)
    assert r.status_code == 201 and len(manuels(env)) == 1


async def test_envoye_identique_a_une_proposition_declaree_relie(env):
    env.llm = reponse("Idées.\n" + BLOC)
    await env.client.post("/api/v1/chat/stream", json={"message": "Aide-moi à lui répondre",
                          "conversation_id": CHAT, "whatsapp_analysis": "allowed"}, headers=auth_headers())
    await chat.wait_background_tasks()
    ligne = [r for r in env.supa.inserted if r["role"] == "assistant"][-1]
    p = aide.lues(ligne["attachments"], ligne["id"])
    prop = p["tons"][1]["propositions"][0]
    await env.client.put(f"/api/v1/conversations/{CHAT}/messages/{ligne['id']}/propositions/{prop['id']}/envoyee",
                         headers=auth_headers())
    r = await ajouter(env, message("sent", prop["texte"]))
    assert r.status_code == 409
    [c] = r.json()["detail"]["items"]
    assert c["type"] == "declaration" and c["proposition_id"] == prop["id"]
    r = await ajouter(env, message("sent", prop["texte"]), confirmer=True)
    [l] = r.json()["messages"]
    assert l["declared_proposition_id"] == prop["id"] and l["origin"] == "manual_sent"
    # La mémoire sait que ce n'est pas un second échange.
    env.llm = reponse("Ok.")
    await env.client.post("/api/v1/chat/stream", json={"message": "Que lui dire ensuite ?",
                          "conversation_id": CHAT, "whatsapp_analysis": "allowed"}, headers=auth_headers())
    assert "ne la compte pas deux fois" in env.llm.calls[0]["messages"][-2]["content"]


# --- Correction, suppression, protection, isolation ----------------------------

async def test_corriger_puis_supprimer_un_ajout(env):
    [l] = (await ajouter(env, message("received", "Ah bon ? Et tu comptais me le dire quand"))).json()["messages"]
    base = f"/api/v1/contexts/{CTX_PEPPER}/messages/{l['id']}"
    r = await env.client.patch(base, json={"content": "Ah bon ? Et tu comptais me le dire quand ?",
                                           "sent_at": "2026-10-16T10:00:00", "sent_at_raw": "16/10/2026 10:00"},
                               headers=auth_headers())
    assert r.status_code == 200 and r.json()["content"].endswith("?") and r.json()["edited_at"]
    assert r.json()["origin"] == "manual_received"
    assert (await env.client.delete(base, headers=auth_headers())).status_code == 204
    assert manuels(env) == []
    assert (await env.client.delete(base, headers=auth_headers())).status_code == 404


async def test_messages_importes_intouchables(env):
    export = env.supa.context_messages[CTX_PEPPER][0]
    export["id"] = str(uuid4())
    texte = export["content"]
    base = f"/api/v1/contexts/{CTX_PEPPER}/messages/{export['id']}"
    r = await env.client.patch(base, json={"content": "falsifié"}, headers=auth_headers())
    assert r.status_code == 409 and r.json()["detail"]["code"] == "message_original"
    assert (await env.client.delete(base, headers=auth_headers())).status_code == 409
    assert env.supa.context_messages[CTX_PEPPER][0]["content"] == texte == pepper()[0]["content"]


async def test_isolation_entre_comptes(env):
    r = await ajouter(env, message("received", "Intrus"), headers=entetes(AUTRE))
    assert r.status_code == 404 and manuels(env) == []
    [l] = (await ajouter(env, message("received", "À moi"))).json()["messages"]
    base = f"/api/v1/contexts/{CTX_PEPPER}/messages/{l['id']}"
    assert (await env.client.patch(base, json={"content": "x"}, headers=entetes(AUTRE))).status_code == 404
    assert (await env.client.delete(base, headers=entetes(AUTRE))).status_code == 404
    assert (await env.client.get("/api/v1/contexts", headers=entetes(AUTRE))).json() == {"items": []}
    items = (await env.client.get("/api/v1/contexts", headers=auth_headers())).json()["items"]
    assert [i["contact_name"] for i in items] == ["Pepper Potts"]


# --- Moteur : contexte à jour, provenance, références --------------------------

async def test_question_suivante_voit_le_message_colle(env):
    # Une première question remplit le cache Redis des messages.
    await env.client.post("/api/v1/chat/stream", json={"message": "Résume", "conversation_id": CHAT,
                          "whatsapp_analysis": "allowed"}, headers=auth_headers())
    assert await env.redis.get(cle_cache(CTX_PEPPER))
    await ajouter(env, message("received", "Ah bon ? Et tu comptais me le dire quand ?"))
    assert not await env.redis.get(cle_cache(CTX_PEPPER))       # cache vidé : contexte à jour
    env.llm = reponse("Elle t'a écrit « Ah bon ? Et tu comptais me le dire quand ? ».")
    resp = await env.client.post("/api/v1/chat/stream", json={"message": "Tu penses quoi de sa réponse ?",
                                 "conversation_id": CHAT, "whatsapp_analysis": "allowed"}, headers=auth_headers())
    systeme = env.llm.calls[0]["messages"][0]["content"]
    assert "Pepper Potts (ajouté à la main) : «Ah bon ? Et tu comptais me le dire quand ?»" in systeme
    import re
    # Ajout sans date : clairement APRÈS l'export (vu en réel : « date
    # inconnue » le faisait passer pour plus ancien que le dernier daté).
    assert re.search(r"\[\d+\] après l'export \(date inconnue\) · Pepper Potts \(ajouté à la main\) : «Ah bon",
                     systeme)
    assert ("- Dernier message : de Pepper Potts, ajouté à la main après l'export, date inconnue : "
            "«Ah bon ? Et tu comptais me le dire quand ?»") in systeme
    assert "la suite la PLUS RÉCENTE" in systeme
    # « sa réponse » : le message visé est nommé juste avant la question.
    rappel = env.llm.calls[0]["messages"][-2]
    assert rappel["role"] == "system" and "<message_vise>" in rappel["content"]
    assert re.search(r"MESSAGE VISÉ \(identifiant [^)]+\) : \[\d+\] après l'export \(date inconnue\) · Pepper Potts, "
                     r"ajouté à la main : «Ah bon \? Et tu comptais me le dire quand \?»", rappel["content"])
    assert "Situation : Pepper Potts a écrit en dernier" in systeme
    # La référence vers le message collé porte sa provenance.
    refs = next(d for e, d in evenements(resp.text) if e == "references")["references"]
    assert refs[0]["origin"] == "manual_received" and refs[0]["excerpt"].startswith("Ah bon")


async def test_reference_vers_un_ajout_supprime_disparait(env):
    [l] = (await ajouter(env, message("received", "Message à supprimer"))).json()["messages"]
    env.llm = reponse("Elle a écrit « Message à supprimer ».")
    await env.client.post("/api/v1/chat/stream", json={"message": "Et ça ?", "conversation_id": CHAT,
                          "whatsapp_analysis": "allowed"}, headers=auth_headers())
    await chat.wait_background_tasks()
    items = (await env.client.get(f"/api/v1/conversations/{CHAT}/references", headers=auth_headers())).json()["items"]
    assert any(r["context_message_id"] == l["id"] for i in items for r in i["references"])
    await env.client.delete(f"/api/v1/contexts/{CTX_PEPPER}/messages/{l['id']}", headers=auth_headers())
    items = (await env.client.get(f"/api/v1/conversations/{CHAT}/references", headers=auth_headers())).json()["items"]
    assert not any(r["context_message_id"] == l["id"] for i in items for r in i["references"])


async def test_page_de_messages_avec_provenance(env):
    await ajouter(env, message("sent", "Je serai là samedi"))
    r = await env.client.get(f"/api/v1/contexts/{CTX_PEPPER}/messages?after=-1&limit=200", headers=auth_headers())
    msgs = r.json()["messages"]
    assert msgs[0]["origin"] == "export" and msgs[-1]["origin"] == "manual_sent"
    assert msgs[-1]["id"] and msgs[-1]["author"] == "Tony Stark"


async def test_page_des_seuls_ajouts(env):
    await ajouter(env, message("received", "Un"), message("sent", "Deux"))
    r = await env.client.get(f"/api/v1/contexts/{CTX_PEPPER}/messages?after=-1&manual=true", headers=auth_headers())
    assert [m["content"] for m in r.json()["messages"]] == ["Un", "Deux"]


async def test_preflight_cors_web_pour_corriger_et_supprimer():
    from app.main import app as application
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=application), base_url="http://test") as client:
        for methode in ("POST", "PATCH", "DELETE"):
            r = await client.options(f"/api/v1/contexts/{CTX_PEPPER}/messages/{uuid4()}", headers={
                "Origin": "http://localhost:3000", "Access-Control-Request-Method": methode,
                "Access-Control-Request-Headers": "authorization,content-type"})
            assert r.status_code == 200 and methode in r.headers["access-control-allow-methods"], methode
