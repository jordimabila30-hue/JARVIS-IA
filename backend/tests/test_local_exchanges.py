import time
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from uuid import uuid4

import httpx
import jwt
import pytest_asyncio
from fastapi import FastAPI

from app.api.v1 import local_exchanges
from app.api.v1.chat import context_key
from app.config import get_settings
from app.quota import requests_key, utc_now
from app.redis_client import get_redis
from app.supabase_client import get_supabase

USER = "11111111-1111-1111-1111-111111111111"
OTHER_USER = "99999999-9999-9999-9999-999999999999"
OWN_CONV = "33333333-3333-3333-3333-333333333333"
OTHER_CONV = "22222222-2222-2222-2222-222222222222"
NEW_CONV = "44444444-4444-4444-4444-444444444444"
settings = get_settings()


class FakeSupabase:
    """Tables `conversations` et `messages` en mémoire (la RLS n'existe pas
    côté service_role : la route doit contrôler elle-même le propriétaire)."""

    def __init__(self):
        self.conversations = {
            OWN_CONV: USER,
            OTHER_CONV: OTHER_USER,
        }
        self.messages: dict[str, dict] = {}
        self.created = []
        self.down = False
        self.conflict_once = False

    def _check(self):
        if self.down:
            raise httpx.ConnectError("Supabase injoignable")

    async def get_message(self, message_id):
        self._check()
        m = self.messages.get(message_id)
        return None if m is None else {
            "id": message_id,
            "conversation_id": m["conversation_id"],
            "user_id": m["user_id"],
        }

    async def get_conversation(self, conversation_id, user_id):
        self._check()
        if self.conversations.get(conversation_id) == user_id:
            return {"id": conversation_id, "title": "Ancienne", "persona": None}
        return None

    async def create_conversation(self, user_id, title):
        self._check()
        self.conversations[NEW_CONV] = user_id
        self.created.append((user_id, title))
        return {"id": NEW_CONV, "title": title, "persona": None}

    async def insert_messages(self, rows):
        self._check()
        if self.conflict_once:
            # Un envoi concurrent a déjà enregistré l'échange.
            self.conflict_once = False
            for row in rows:
                self.messages[row["id"]] = row
            request = httpx.Request("POST", "http://supabase/messages")
            raise httpx.HTTPStatusError(
                "conflict", request=request, response=httpx.Response(409, request=request)
            )
        for row in rows:
            assert row["id"] not in self.messages
            self.messages[row["id"]] = row


@pytest_asyncio.fixture
async def env(redis):
    supa = FakeSupabase()
    app = FastAPI()
    app.include_router(local_exchanges.router, prefix="/api/v1")
    app.dependency_overrides[get_supabase] = lambda: supa
    app.dependency_overrides[get_redis] = lambda: redis
    client = httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test")
    yield SimpleNamespace(client=client, redis=redis, supa=supa)
    await client.aclose()


def auth_headers(sub=USER):
    token = jwt.encode(
        {"sub": sub, "role": "authenticated", "aud": "authenticated",
         "iss": settings.supabase_issuer, "exp": int(time.time()) + 3600},
        settings.supabase_jwt_secret,
        algorithm="HS256",
    )
    return {"Authorization": f"Bearer {token}"}


def body(**extra):
    data = {
        "question_id": str(uuid4()),
        "answer_id": str(uuid4()),
        "question": "Combien font 6 fois 7 ?",
        "answer": "6 fois 7 égale 42.",
    }
    data.update(extra)
    return data


async def post(env, data, headers=None):
    return await env.client.post(
        "/api/v1/conversations/local-exchanges",
        json=data,
        headers=auth_headers() if headers is None else headers,
    )


async def test_requires_valid_jwt(env):
    resp = await post(env, body(), headers={})
    assert resp.status_code == 401
    resp = await post(env, body(), headers={"Authorization": "Bearer pas.un.jeton"})
    assert resp.status_code == 401
    assert env.supa.messages == {}


async def test_new_conversation_created_for_jwt_user_only(env):
    # Un user_id fourni par le client est ignoré : seul le JWT compte.
    data = body(user_id=OTHER_USER)
    resp = await post(env, data)

    assert resp.status_code == 201
    assert resp.json()["conversation_id"] == NEW_CONV
    assert resp.json()["already_saved"] is False
    assert env.supa.created == [(USER, "Combien font 6 fois 7 ?")]
    question = env.supa.messages[data["question_id"]]
    answer = env.supa.messages[data["answer_id"]]
    assert question["user_id"] == answer["user_id"] == USER
    assert question["role"] == "user" and "model" not in question
    assert answer["role"] == "assistant"
    assert answer["model"] == local_exchanges.LOCAL_MODEL
    assert answer["content"] == "6 fois 7 égale 42."
    # Aucun quota de génération consommé.
    assert await env.redis.get(requests_key(USER, utc_now().date())) is None


async def test_existing_own_conversation_and_context_reset(env):
    await env.redis.rpush(context_key(OWN_CONV), '{"role": "user", "content": "x"}')
    data = body(conversation_id=OWN_CONV)
    resp = await post(env, data)

    assert resp.status_code == 201
    assert resp.json()["conversation_id"] == OWN_CONV
    assert env.supa.created == []
    assert env.supa.messages[data["question_id"]]["conversation_id"] == OWN_CONV
    # Le contexte de l'IA sera relu dans l'ordre depuis Supabase.
    assert not await env.redis.exists(context_key(OWN_CONV))


async def test_other_users_conversation_refused(env):
    resp = await post(env, body(conversation_id=OTHER_CONV))
    assert resp.status_code == 404
    assert env.supa.messages == {}
    resp = await post(env, body(conversation_id=str(uuid4())))
    assert resp.status_code == 404


async def test_retry_is_idempotent(env):
    data = body(conversation_id=OWN_CONV)
    first = await post(env, data)
    again = await post(env, data)

    assert first.status_code == 201
    assert again.status_code == 200
    assert again.json()["already_saved"] is True
    assert again.json()["conversation_id"] == OWN_CONV
    assert len(env.supa.messages) == 2


async def test_retry_after_lost_response_does_not_create_second_conversation(env):
    data = body()
    await post(env, data)
    again = await post(env, data)
    assert again.json()["conversation_id"] == NEW_CONV
    assert len(env.supa.created) == 1


async def test_concurrent_duplicate_is_reported_as_saved(env):
    env.supa.conflict_once = True
    resp = await post(env, body(conversation_id=OWN_CONV))
    assert resp.status_code == 200
    assert resp.json()["already_saved"] is True


async def test_id_of_another_user_refused(env):
    taken = str(uuid4())
    env.supa.messages[taken] = {"conversation_id": OTHER_CONV, "user_id": OTHER_USER}
    resp = await post(env, body(question_id=taken, conversation_id=OWN_CONV))
    assert resp.status_code == 409
    assert len(env.supa.messages) == 1


async def test_device_times_bounded_and_ordered(env):
    now = datetime.now(timezone.utc)
    past = now - timedelta(minutes=10)
    data = body(
        conversation_id=OWN_CONV,
        question_at=past.isoformat(),
        answer_at=(past - timedelta(minutes=1)).isoformat(),
    )
    await post(env, data)
    q = datetime.fromisoformat(env.supa.messages[data["question_id"]]["created_at"])
    a = datetime.fromisoformat(env.supa.messages[data["answer_id"]]["created_at"])
    assert abs((q - past).total_seconds()) < 1
    assert a >= q  # jamais de réponse avant la question

    future = body(conversation_id=OWN_CONV, question_at=(now + timedelta(days=1)).isoformat())
    await post(env, future)
    q = datetime.fromisoformat(env.supa.messages[future["question_id"]]["created_at"])
    assert q <= datetime.now(timezone.utc)


async def test_invalid_bodies(env):
    same = str(uuid4())
    assert (await post(env, body(question_id=same, answer_id=same))).status_code == 422
    assert (await post(env, body(question=""))).status_code == 422
    assert (await post(env, body(answer="x" * 8001))).status_code == 422


async def test_database_unavailable(env):
    env.supa.down = True
    resp = await post(env, body())
    assert resp.status_code == 503
