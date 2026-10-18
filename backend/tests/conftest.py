import os

import fakeredis
import pytest_asyncio
from redis.asyncio import Redis

os.environ.setdefault("SUPABASE_URL", "https://test-project.supabase.co")
os.environ.setdefault("SUPABASE_SERVICE_ROLE_KEY", "service-role-test")
os.environ.setdefault("SUPABASE_JWT_SECRET", "test-secret-with-at-least-32-characters!!")
os.environ.setdefault("OPENAI_API_KEY", "sk-test")
# Les tests ne dépendent jamais de la configuration privée (backend/.env,
# celle de la production) : bascules fixées ici, Google non configuré.
for _cle, _valeur in {"ABONNEMENTS_ROUTAGE": "false", "ODO_ACTIF": "false", "ODO_OUTILS_FICTIFS": "false",
                      "ENVIRONNEMENT": "production", "LLM_SELECTION_MANUELLE": "false", "LLM_ADMINS": "[]",
                      "GOOGLE_CLIENT_ID": "", "GOOGLE_CLIENT_SECRET": "", "GOOGLE_REDIRECT_URI": ""}.items():
    os.environ[_cle] = _valeur

# REDIS_TEST_URL=redis://localhost:6379/15 -> tests sur un vrai Redis
# (base dédiée, vidée à chaque test). Sinon : Redis simulé (fakeredis).
REDIS_TEST_URL = os.environ.get("REDIS_TEST_URL")


@pytest_asyncio.fixture
async def redis():
    if REDIS_TEST_URL:
        r = Redis.from_url(REDIS_TEST_URL, decode_responses=True)
        await r.flushdb()
    else:
        r = fakeredis.FakeAsyncRedis(decode_responses=True)
    yield r
    if REDIS_TEST_URL:
        await r.flushdb()
    await r.aclose()
