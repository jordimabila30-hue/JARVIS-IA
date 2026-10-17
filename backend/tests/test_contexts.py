"""Contextes WhatsApp : enregistrement, lecture, pagination, suppression.

Supabase est simulé en mémoire, avec la même règle que la fonction SQL
`enregistrer_contexte_whatsapp` : tout ou rien (les tests SQL, eux, vérifient
la vraie transaction : supabase/tests/20_enregistrer_contexte_test.sql).
"""

import copy
import json
import time
from types import SimpleNamespace
from uuid import uuid4

import httpx
import jwt
import pytest_asyncio
from fastapi import FastAPI

from app.api.v1 import chat, contexts
from app.config import get_settings
from app.redis_client import get_redis
from app.supabase_client import get_supabase

USER = "11111111-1111-1111-1111-111111111111"
OTHER_USER = "99999999-9999-9999-9999-999999999999"
OWN_CONV = "33333333-3333-3333-3333-333333333333"
OTHER_CONV = "22222222-2222-2222-2222-222222222222"
settings = get_settings()


def _erreur(status: int, code: str) -> httpx.HTTPStatusError:
    request = httpx.Request("POST", "http://supabase/rpc")
    response = httpx.Response(status, request=request, content=json.dumps({"code": code}))
    return httpx.HTTPStatusError("erreur", request=request, response=response)


class FakeSupabase:
    """Tables en mémoire. La clé service_role contourne la RLS : le code
    testé doit filtrer lui-même par compte."""

    def __init__(self):
        self.conversations = {
            OWN_CONV: {"user_id": USER, "title": "Capitale de la RDC"},
            OTHER_CONV: {"user_id": OTHER_USER, "title": "Chat de l'autre"},
        }
        self.messages = {
            "m-ancien-1": {"conversation_id": OWN_CONV, "user_id": USER, "role": "user",
                           "content": "Quelle est la capitale de la RDC ?"},
            "m-ancien-2": {"conversation_id": OWN_CONV, "user_id": USER, "role": "assistant",
                           "content": "Kinshasa."},
        }
        self.contexts: dict[str, dict] = {}
        self.context_messages: dict[str, list[dict]] = {}
        self.down = False
        self.fail_after_write = False   # transaction annulée en cours de route
        self.timeout_after_commit = False
        self.conflict_once = False
        self.rpc_calls = 0

    def _check(self):
        if self.down:
            raise httpx.ConnectError("Supabase injoignable")

    # --- conversations -----------------------------------------------------

    async def get_conversation(self, conversation_id, user_id):
        self._check()
        c = self.conversations.get(conversation_id)
        if c is None or c["user_id"] != user_id:
            return None
        return {"id": conversation_id, "title": c["title"], "persona": None}

    # --- RPC transactionnelle ---------------------------------------------

    async def save_whatsapp_context(self, params, *, timeout=30.0):
        self._check()
        self.rpc_calls += 1
        if self.conflict_once:
            # Un envoi concurrent a gagné : sa transaction est complète.
            self.conflict_once = False
            self._appliquer(copy.deepcopy(params))
            raise _erreur(409, "23505")
        # Copie de l'état : une erreur annule tout (comme une transaction).
        sauvegarde = copy.deepcopy(
            (self.conversations, self.messages, self.contexts, self.context_messages)
        )
        try:
            resultat = self._appliquer(params)
            if self.fail_after_write:
                raise _erreur(500, "XX000")
        except Exception:
            (self.conversations, self.messages,
             self.contexts, self.context_messages) = sauvegarde
            raise
        if self.timeout_after_commit:
            self.timeout_after_commit = False
            raise httpx.ReadTimeout("délai dépassé")
        return resultat

    def _appliquer(self, p):
        user, ctx_id, msg_id = p["p_user_id"], p["p_context_id"], p["p_message_id"]
        existant = self.contexts.get(ctx_id)
        if existant is not None:
            if existant["user_id"] != user:
                raise _erreur(400, "JVC02")
            return {"already_saved": True, "conversation_id": existant["conversation_id"],
                    "message_id": existant["message_id"], "context_id": ctx_id,
                    "conversation_created": False,
                    "messages_count": len(self.context_messages[ctx_id])}
        if msg_id in self.messages:
            raise _erreur(400, "JVC03")
        titre = p["p_contexte"]["contact_name"]
        conv = p["p_conversation_id"]
        nouvelle = conv is None
        if nouvelle:
            conv = str(uuid4())
            self.conversations[conv] = {"user_id": user, "title": titre}
        else:
            c = self.conversations.get(conv)
            if c is None or c["user_id"] != user:
                raise _erreur(400, "JVC01")
            c["title"] = titre
        self.messages[msg_id] = {"conversation_id": conv, "user_id": user,
                                 "role": "user", "content": p["p_consigne"]}
        self.contexts[ctx_id] = {"id": ctx_id, "user_id": user, "conversation_id": conv,
                                 "message_id": msg_id, "source": "whatsapp",
                                 "created_at": f"2026-10-15T10:00:{len(self.contexts):02d}+00:00",
                                 **{k: v for k, v in p["p_contexte"].items()}}
        rangs = set()
        self.context_messages[ctx_id] = []
        for m in p["p_messages"]:
            if m["kind"] not in ("text", "media", "deleted", "system"):
                raise _erreur(400, "23514")
            rangs.add(m["message_order"])
            self.context_messages[ctx_id].append({**m, "user_id": user})
        return {"already_saved": False, "conversation_id": conv, "message_id": msg_id,
                "context_id": ctx_id, "conversation_created": nouvelle,
                "messages_count": len(p["p_messages"])}

    # --- lecture / suppression (filtrées par compte) ------------------------

    def _ligne(self, c):
        champs = {k: c.get(k) for k in (
            "id", "conversation_id", "message_id", "source", "contact_name", "is_group",
            "current_user_name", "participants", "period_start", "period_end",
            "dates_uncertain", "created_at")}
        champs["participants"] = champs["participants"] or []
        champs["is_group"] = bool(champs["is_group"])
        champs["dates_uncertain"] = bool(champs["dates_uncertain"])
        return {**champs, "context_messages": [{"count": len(self.context_messages[c["id"]])}]}

    async def list_contexts(self, conversation_id, user_id):
        self._check()
        return [self._ligne(c) for c in self.contexts.values()
                if c["conversation_id"] == conversation_id and c["user_id"] == user_id]

    async def get_context(self, context_id, user_id):
        self._check()
        c = self.contexts.get(context_id)
        return None if c is None or c["user_id"] != user_id else self._ligne(c)

    async def list_context_messages(self, context_id, user_id, *, after, limit):
        self._check()
        c = self.contexts.get(context_id)
        if c is None or c["user_id"] != user_id:
            return []
        rangs = sorted(self.context_messages[context_id], key=lambda m: m["message_order"])
        return [{k: v for k, v in m.items() if k != "user_id"}
                for m in rangs if m["message_order"] > after][:limit]

    async def delete_context(self, context_id, user_id):
        self._check()
        c = self.contexts.get(context_id)
        if c is None or c["user_id"] != user_id:
            return False
        del self.contexts[context_id]
        del self.context_messages[context_id]   # cascade
        return True


@pytest_asyncio.fixture
async def env(redis, monkeypatch):
    supa = FakeSupabase()
    # Aucun appel à l'IA ne doit avoir lieu.
    appels_ia = []
    monkeypatch.setattr(chat.selection, "fournisseur", lambda nom=None, settings=None: appels_ia.append(1))
    app = FastAPI()
    app.include_router(contexts.conversations_router, prefix="/api/v1")
    app.include_router(contexts.contexts_router, prefix="/api/v1")
    app.dependency_overrides[get_supabase] = lambda: supa
    app.dependency_overrides[get_redis] = lambda: redis
    client = httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test")
    yield SimpleNamespace(client=client, redis=redis, supa=supa, appels_ia=appels_ia)
    await client.aclose()


def auth(sub=USER):
    token = jwt.encode(
        {"sub": sub, "role": "authenticated", "aud": "authenticated",
         "iss": settings.supabase_issuer, "exp": int(time.time()) + 3600},
        settings.supabase_jwt_secret, algorithm="HS256",
    )
    return {"Authorization": f"Bearer {token}"}


def piece(n=3, conversation_id=OWN_CONV, **extra):
    data = {
        "context_id": str(uuid4()),
        "message_id": str(uuid4()),
        "conversation_id": conversation_id,
        "instruction": "JARVIS, analyse cette conversation.",
        "context": {
            "contact_name": "Tony Stark",
            "current_user_name": "Pepper Potts",
            "participants": ["Tony Stark", "Pepper Potts"],
            "source_fingerprint": "wa-0123456789abcdef",
        },
        "messages": [
            {"message_order": i, "source_order": 10 + i,
             "author": "Tony Stark" if i % 2 == 0 else "Pepper Potts",
             "content": f"message {i}",
             "sent_at": f"2026-10-{12 + i % 3:02d}T09:{i % 60:02d}:00",
             "sent_at_raw": f"{12 + i % 3}/10/2026 09:{i % 60:02d}"}
            for i in range(n)
        ],
    }
    data.update(extra)
    return data


async def envoyer(env, data, headers=None):
    return await env.client.post(
        "/api/v1/conversations/contexts", json=data,
        headers=auth() if headers is None else headers,
    )


# 1. Authentification -------------------------------------------------------

async def test_authentification_obligatoire(env):
    for methode, url in [
        ("POST", "/api/v1/conversations/contexts"),
        ("GET", f"/api/v1/conversations/{OWN_CONV}/contexts"),
        ("GET", f"/api/v1/contexts/{uuid4()}"),
        ("GET", f"/api/v1/contexts/{uuid4()}/messages"),
        ("DELETE", f"/api/v1/contexts/{uuid4()}"),
    ]:
        resp = await env.client.request(methode, url, json=piece() if methode == "POST" else None)
        assert resp.status_code == 401, url
        resp = await env.client.request(methode, url, headers={"Authorization": "Bearer faux"})
        assert resp.status_code == 401, url
    assert env.supa.contexts == {}


# 2-7, 13, 14. Chat existant ------------------------------------------------

async def test_enregistrement_dans_un_chat_existant(env):
    data = piece(5)
    resp = await envoyer(env, data)
    assert resp.status_code == 201
    r = resp.json()
    assert r == {"conversation_id": OWN_CONV, "message_id": data["message_id"],
                 "context_id": data["context_id"], "messages_count": 5,
                 "conversation_created": False, "already_saved": False}
    ctx = env.supa.contexts[data["context_id"]]
    # Bon compte, bon chat, bonne consigne.
    assert ctx["user_id"] == USER
    assert ctx["conversation_id"] == OWN_CONV
    assert ctx["message_id"] == data["message_id"]
    consigne = env.supa.messages[data["message_id"]]
    assert consigne == {"conversation_id": OWN_CONV, "user_id": USER, "role": "user",
                        "content": "JARVIS, analyse cette conversation."}
    # Les messages WhatsApp ne deviennent pas des messages JARVIS.
    assert len(env.supa.messages) == 3
    # Anciens messages intacts ; titre du contact.
    assert env.supa.messages["m-ancien-1"]["content"] == "Quelle est la capitale de la RDC ?"
    assert env.supa.messages["m-ancien-2"]["content"] == "Kinshasa."
    assert env.supa.conversations[OWN_CONV]["title"] == "Tony Stark"
    # Messages sélectionnés, tous, dans l'ordre.
    stockes = env.supa.context_messages[data["context_id"]]
    assert [m["message_order"] for m in stockes] == [0, 1, 2, 3, 4]
    assert all(m["user_id"] == USER for m in stockes)
    # Période calculée sur les vrais messages.
    assert ctx["period_start"] == "2026-10-12T09:00:00"
    assert ctx["period_end"] == "2026-10-14T09:02:00"
    assert env.appels_ia == []


async def test_user_id_du_corps_ignore(env):
    data = piece()
    data["user_id"] = OTHER_USER
    data["context"]["user_id"] = OTHER_USER
    resp = await envoyer(env, data)
    assert resp.status_code == 201
    assert env.supa.contexts[data["context_id"]]["user_id"] == USER


async def test_ordre_conserve_meme_envoye_dans_le_desordre(env):
    data = piece(4)
    data["messages"].reverse()
    resp = await envoyer(env, data)
    assert resp.status_code == 201
    page = (await env.client.get(f"/api/v1/contexts/{data['context_id']}/messages",
                                 headers=auth())).json()
    assert [m["content"] for m in page["messages"]] == [
        "message 0", "message 1", "message 2", "message 3"]


# 12. Accueil vide ------------------------------------------------------------

async def test_creation_depuis_un_accueil_vide(env):
    data = piece(2, conversation_id=None)
    data["context"]["contact_name"] = "Pepper Potts"
    resp = await envoyer(env, data)
    assert resp.status_code == 201
    r = resp.json()
    assert r["conversation_created"] is True
    conv = env.supa.conversations[r["conversation_id"]]
    assert conv == {"user_id": USER, "title": "Pepper Potts"}
    assert env.supa.messages[data["message_id"]]["conversation_id"] == r["conversation_id"]


# 8. Autres comptes -----------------------------------------------------------

async def test_chat_d_un_autre_compte_refuse(env):
    data = piece(conversation_id=OTHER_CONV)
    resp = await envoyer(env, data)
    assert resp.status_code == 404
    assert resp.json()["detail"] == "Conversation introuvable"
    assert env.supa.conversations[OTHER_CONV]["title"] == "Chat de l'autre"
    assert env.supa.contexts == {}


async def test_contexte_d_un_autre_compte_invisible(env):
    data = piece()
    await envoyer(env, data)
    autre = auth(OTHER_USER)
    ctx = data["context_id"]
    assert (await env.client.get(f"/api/v1/contexts/{ctx}", headers=autre)).status_code == 404
    assert (await env.client.get(f"/api/v1/contexts/{ctx}/messages",
                                 headers=autre)).status_code == 404
    assert (await env.client.get(f"/api/v1/conversations/{OWN_CONV}/contexts",
                                 headers=autre)).status_code == 404
    assert (await env.client.delete(f"/api/v1/contexts/{ctx}", headers=autre)).status_code == 404
    assert ctx in env.supa.contexts
    # Réutiliser l'identifiant de contexte d'un autre compte : refusé.
    resp = await envoyer(env, piece(context_id=ctx), headers=autre)
    assert resp.status_code == 409


# 9-11. Lecture ---------------------------------------------------------------

async def test_plusieurs_contextes_dans_un_chat(env):
    premier, second = piece(35), piece(10)
    second["instruction"] = "Analyse les nouveaux échanges."
    assert (await envoyer(env, premier)).status_code == 201
    assert (await envoyer(env, second)).status_code == 201
    resp = await env.client.get(f"/api/v1/conversations/{OWN_CONV}/contexts", headers=auth())
    assert resp.status_code == 200
    liste = resp.json()
    assert [c["id"] for c in liste] == [premier["context_id"], second["context_id"]]
    assert [c["messages_count"] for c in liste] == [35, 10]
    assert all(c["source"] == "whatsapp" and c["contact_name"] == "Tony Stark" for c in liste)
    # Métadonnées seulement : aucun message dans la liste.
    assert "messages" not in liste[0]
    un = (await env.client.get(f"/api/v1/contexts/{premier['context_id']}",
                               headers=auth())).json()
    assert un["messages_count"] == 35
    assert un["message_id"] == premier["message_id"]
    assert un["participants"] == ["Tony Stark", "Pepper Potts"]


async def test_messages_pagines(env):
    data = piece(450)
    await envoyer(env, data)
    url = f"/api/v1/contexts/{data['context_id']}/messages"
    vus, after, pages = [], -1, 0
    while True:
        page = (await env.client.get(url, params={"after": after, "limit": 200},
                                     headers=auth())).json()
        vus += [m["message_order"] for m in page["messages"]]
        pages += 1
        if page["next_after"] is None:
            break
        after = page["next_after"]
    assert vus == list(range(450))
    assert pages == 3
    # Taille de page bornée par la configuration.
    page = (await env.client.get(url, params={"limit": 100000}, headers=auth())).json()
    assert len(page["messages"]) == min(450, settings.whatsapp_context_page_max)
    # Dates : sans fuseau ; date illisible acceptée sans être inventée.
    assert page["messages"][0]["sent_at"] == "2026-10-12T09:00:00"


async def test_date_illisible_acceptee_sans_invention(env):
    data = piece(1)
    data["messages"][0].update(sent_at=None, sent_at_raw="32/13/2026 25:61")
    assert (await envoyer(env, data)).status_code == 201
    stocke = env.supa.context_messages[data["context_id"]][0]
    assert stocke["sent_at"] is None and stocke["sent_at_raw"] == "32/13/2026 25:61"
    assert env.supa.contexts[data["context_id"]]["period_start"] is None


# 15-17. Suppression ---------------------------------------------------------

async def test_suppression_d_un_contexte_seulement(env):
    premier, second = piece(3), piece(2)
    await envoyer(env, premier)
    await envoyer(env, second)
    resp = await env.client.delete(f"/api/v1/contexts/{premier['context_id']}", headers=auth())
    assert resp.status_code == 204
    assert premier["context_id"] not in env.supa.contexts
    assert premier["context_id"] not in env.supa.context_messages   # cascade
    # Rien d'autre : le chat, la consigne, l'autre pièce jointe restent.
    assert OWN_CONV in env.supa.conversations
    assert premier["message_id"] in env.supa.messages
    assert second["context_id"] in env.supa.contexts
    again = await env.client.delete(f"/api/v1/contexts/{premier['context_id']}", headers=auth())
    assert again.status_code == 404


# 18-20. Erreurs, enregistrement partiel, réessais ----------------------------

async def test_supabase_indisponible(env):
    env.supa.down = True
    resp = await envoyer(env, piece())
    assert resp.status_code == 503
    assert resp.json()["detail"] == "Base de données indisponible"
    resp = await env.client.get(f"/api/v1/conversations/{OWN_CONV}/contexts", headers=auth())
    assert resp.status_code == 503


async def test_jamais_de_succes_pour_un_enregistrement_partiel(env, caplog):
    env.supa.fail_after_write = True
    data = piece(35)
    resp = await envoyer(env, data)
    assert resp.status_code == 503
    # Rien n'a été gardé : ni consigne, ni contexte, ni messages, ni titre.
    assert env.supa.contexts == {} and env.supa.context_messages == {}
    assert data["message_id"] not in env.supa.messages
    assert env.supa.conversations[OWN_CONV]["title"] == "Capitale de la RDC"
    # Aucun contenu privé dans le journal.
    assert "message 3" not in caplog.text


async def test_reessai_apres_coupure_sans_doublon(env):
    data = piece(35)
    env.supa.timeout_after_commit = True
    resp = await envoyer(env, data)
    assert resp.status_code == 503           # l'appareil ne sait pas
    resp = await envoyer(env, data)          # il réessaie, même context_id
    assert resp.status_code == 200
    assert resp.json()["already_saved"] is True
    assert resp.json()["messages_count"] == 35
    assert len(env.supa.contexts) == 1
    assert len(env.supa.context_messages[data["context_id"]]) == 35
    assert sum(1 for m in env.supa.messages.values() if m["role"] == "user") == 2


async def test_deux_envois_simultanes(env):
    data = piece(5)
    env.supa.conflict_once = True
    resp = await envoyer(env, data)
    assert resp.status_code == 200
    assert resp.json()["already_saved"] is True
    assert resp.json()["messages_count"] == 5
    assert len(env.supa.contexts) == 1


async def test_meme_selection_deux_fois_avec_nouvel_identifiant(env):
    # Même export (même empreinte), nouvelle pièce jointe voulue : un
    # second contexte, sans fusion.
    a, b = piece(3), piece(3)
    assert (await envoyer(env, a)).status_code == 201
    assert (await envoyer(env, b)).status_code == 201
    assert len(env.supa.contexts) == 2


# Validation -------------------------------------------------------------------

async def test_donnees_invalides(env):
    cas = []
    d = piece(); d["context"]["contact_name"] = "   "; cas.append(d)
    d = piece(); d["context"]["source"] = "telegram"; cas.append(d)
    d = piece(); d["instruction"] = "  "; cas.append(d)
    d = piece(); d["messages"] = []; cas.append(d)
    d = piece(3); d["messages"][2]["message_order"] = 5; cas.append(d)          # trou
    d = piece(3); d["messages"][2]["message_order"] = 1; cas.append(d)          # doublon
    d = piece(); d["messages"][0]["kind"] = "inconnu"; cas.append(d)
    d = piece(); d["messages"][0]["sent_at"] = "2026-10-12T09:00:00+02:00"; cas.append(d)
    d = piece(); d["context_id"] = "pas-un-uuid"; cas.append(d)
    d = piece(); d["message_id"] = d["context_id"]; cas.append(d)
    for data in cas:
        resp = await envoyer(env, data)
        assert resp.status_code == 422, data
        assert "message 0" not in resp.text      # jamais le contenu
    assert env.supa.rpc_calls == 0


async def test_requete_trop_volumineuse(env, monkeypatch):
    monkeypatch.setattr(settings, "whatsapp_context_max_messages", 100)
    resp = await envoyer(env, piece(101))
    assert resp.status_code == 413
    monkeypatch.setattr(settings, "whatsapp_context_max_bytes", 1000)
    resp = await envoyer(env, piece(50))
    assert resp.status_code == 413
    assert env.supa.rpc_calls == 0


# 21. Grande sélection -------------------------------------------------------

async def test_grande_selection(env):
    data = piece(5000)
    resp = await envoyer(env, data)
    assert resp.status_code == 201
    assert resp.json()["messages_count"] == 5000
    assert env.supa.rpc_calls == 1           # un seul appel, une transaction


# 22. Pas d'IA (23 : la suite complète couvre les routes existantes) --------------------------------------------

async def test_aucun_appel_ia_et_contexte_court_invalide(env):
    await env.redis.set(f"ctx:{OWN_CONV}", "ancien")
    resp = await envoyer(env, piece())
    assert resp.status_code == 201
    assert env.appels_ia == []
    assert await env.redis.get(f"ctx:{OWN_CONV}") is None
