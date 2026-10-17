"""Abonnements Free & Pro, phase 2 : limites effectives, sessions, routage MIA,
/me/quota, contrôle avant l'appel. Aucun appel réel (fournisseurs simulés).

La règle des limites effectives (offre, sauf exception) est calculée en SQL
(`limites_effectives`, testée dans supabase/tests/60_*) ; le faux Supabase
ci-dessous l'applique de la même façon pour exercer le backend.
"""

import asyncio
from dataclasses import replace
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from uuid import uuid4

import httpx
import pytest
from fastapi import FastAPI, HTTPException
from starlette.requests import Request

from app import quota as quota_mod
from app.api.v1 import chat
from app.auth import AuthUser, get_current_user
from app.config import get_settings
from app.llm import FournisseurNonConfigure
from app.quota import (
    QuotaReservation,
    QuotaService,
    get_quota_service,
    limits_key,
    requests_key,
    session_active_key,
)
from app.redis_client import get_redis
from app.supabase_client import SessionUsage, UserLimits, get_supabase
from test_chat import USER, FakeOpenAI, FakeSupabase, auth_headers, chunk, fournisseur_test, parse_sse

settings = get_settings()
DEBUT = datetime(2026, 10, 17, 10, 0, tzinfo=timezone.utc)

OFFRES = {
    "free": dict(llm_provider="groq", llm_model="openai/gpt-oss-120b", daily_message_limit=100,
                 daily_token_limit=50_000, session_duration_minutes=300, session_message_limit=25,
                 session_token_limit=15_000, critical_threshold_percent=80),
    "pro": dict(llm_provider="anthropic", llm_model="claude-opus-5-5", daily_message_limit=200,
                daily_token_limit=100_000, session_duration_minutes=300, session_message_limit=50,
                session_token_limit=30_000, critical_threshold_percent=80),
}


class Horloge:
    def __init__(self):
        self.maintenant = DEBUT

    def __call__(self):
        return self.maintenant

    def avancer(self, **duree):
        self.maintenant += timedelta(**duree)


class SupabaseAbo(FakeSupabase):
    """users + plan_config + quota_usage + usage_sessions + llm_usage."""

    def __init__(self, horloge: Horloge, plan="pro", **compte):
        super().__init__()
        self.horloge = horloge
        self.offres = {k: dict(v) for k, v in OFFRES.items()}
        self.compte = {"plan": plan, "limits_override": False, "daily_message_limit": 60,
                       "daily_token_limit": 100_000, **compte}
        self.jour = (0, 0)
        self.sessions: list[dict] = []
        self.llm: list[tuple] = []
        self.verrou = asyncio.Lock()
        self.lectures_limites = 0

    async def get_user_limits(self, user_id):
        self.lectures_limites += 1
        c, o = self.compte, self.offres[self.compte["plan"]]
        exception = c["limits_override"]
        return UserLimits(
            plan=c["plan"], exception=exception,
            daily_message_limit=c["daily_message_limit"] if exception else o["daily_message_limit"],
            daily_token_limit=c["daily_token_limit"] if exception else o["daily_token_limit"],
            llm_provider=o["llm_provider"], llm_model=o["llm_model"],
            session_duration_minutes=o["session_duration_minutes"],
            session_message_limit=o["session_message_limit"], session_token_limit=o["session_token_limit"],
            critical_threshold_percent=o["critical_threshold_percent"],
        )

    async def get_daily_usage(self, user_id, day):
        return self.jour

    async def increment_quota_usage(self, user_id, messages, tokens):
        self.increments.append((messages, tokens))
        self.jour = (self.jour[0] + messages, self.jour[1] + tokens)

    def _usage(self, s):
        return SessionUsage(id=s["id"], plan=s["plan"], started_at=s["started_at"], ends_at=s["ends_at"],
                            messages_used=s["messages_used"], tokens_used=s["tokens_used"])

    def _active(self):
        actives = [s for s in self.sessions if s["ends_at"] > self.horloge()]
        return max(actives, key=lambda s: s["started_at"]) if actives else None

    async def session_active(self, user_id):
        s = self._active()
        return self._usage(s) if s else None

    async def ouvrir_session(self, user_id, plan, duree_minutes):
        async with self.verrou:              # pg_advisory_xact_lock
            await asyncio.sleep(0)
            s = self._active()
            if s is None:
                debut = self.horloge()
                s = {"id": str(uuid4()), "plan": plan, "started_at": debut,
                     "ends_at": debut + timedelta(minutes=duree_minutes), "messages_used": 0, "tokens_used": 0}
                self.sessions.append(s)
            return self._usage(s)

    async def increment_session_usage(self, session_id, user_id, messages, tokens):
        for s in self.sessions:
            if s["id"] == session_id:
                s["messages_used"] += messages
                s["tokens_used"] += tokens

    async def increment_llm_usage(self, user_id, provider, model, requests, tokens_input, tokens_output):
        self.llm.append((provider, model, requests, tokens_input, tokens_output))


@pytest.fixture
def horloge(monkeypatch):
    h = Horloge()
    monkeypatch.setattr(quota_mod, "utc_now", h)
    return h


def service(redis, supa) -> QuotaService:
    return QuotaService(redis, supa, limits_cache_ttl=30)


def reservation(statut) -> QuotaReservation:
    return QuotaReservation(user=AuthUser(id=USER, email=None, role="authenticated"), status=statut)


# --- Limites effectives : l'offre, sauf exception ----------------------------------

async def test_compte_pro_suit_l_offre_malgre_ses_anciennes_valeurs(redis, horloge):
    supa = SupabaseAbo(horloge, plan="pro", daily_message_limit=60)
    limites = await service(redis, supa).get_limits(USER)
    assert (limites.daily_message_limit, limites.daily_token_limit) == (200, 100_000)
    assert limites.llm_provider == "anthropic" and limites.llm_model == "claude-opus-5-5"
    assert not limites.exception


async def test_compte_free_herite_de_l_offre_free(redis, horloge):
    limites = await service(redis, SupabaseAbo(horloge, plan="free")).get_limits(USER)
    assert (limites.daily_message_limit, limites.daily_token_limit, limites.llm_provider) == (100, 50_000, "groq")


async def test_exception_seulement_si_activee(redis, horloge):
    supa = SupabaseAbo(horloge, plan="free", limits_override=True, daily_message_limit=500, daily_token_limit=None)
    limites = await service(redis, supa).get_limits(USER)
    assert (limites.daily_message_limit, limites.daily_token_limit, limites.exception) == (500, None, True)
    assert limites.session_message_limit == 25          # la session reste celle de l'offre


async def test_modification_de_plan_config_prise_en_compte_apres_le_cache(redis, horloge):
    supa = SupabaseAbo(horloge, plan="free")
    svc = service(redis, supa)
    assert (await svc.get_limits(USER)).daily_message_limit == 100
    supa.offres["free"]["daily_message_limit"] = 150              # éditeur de tables
    assert (await svc.get_limits(USER)).daily_message_limit == 100   # encore en cache
    assert 0 < await redis.ttl(limits_key(USER)) <= 30               # délai maximal : 30 s
    await redis.delete(limits_key(USER))                             # expiration du cache
    assert (await svc.get_limits(USER)).daily_message_limit == 150
    assert supa.lectures_limites == 2


# --- Sessions -----------------------------------------------------------------------

async def test_session_ouverte_au_premier_appel_pour_5_heures(redis, horloge):
    supa = SupabaseAbo(horloge)
    svc = service(redis, supa)
    assert supa.sessions == []
    q1 = await svc.reserve(USER)
    assert q1.session.started_at == DEBUT and q1.session.ends_at == DEBUT + timedelta(hours=5)
    assert q1.session.duration_minutes == 300 and q1.session.messages_used == 1
    horloge.avancer(hours=3)
    q2 = await svc.reserve(USER)
    assert q2.session.id == q1.session.id and q2.session.messages_used == 2
    assert q2.session.resets_in == 2 * 3600
    assert len(supa.sessions) == 1


async def test_limite_de_session_puis_renouvellement_sans_toucher_au_jour(redis, horloge):
    supa = SupabaseAbo(horloge)
    supa.offres["pro"]["session_message_limit"] = 3
    svc = service(redis, supa)
    for _ in range(3):
        await svc.reserve(USER)
    horloge.avancer(hours=3)
    with pytest.raises(HTTPException) as e:
        await svc.reserve(USER)
    detail = e.value.detail
    assert e.value.status_code == 429 and detail["kind"] == "session_messages"
    assert detail["resets_in"] == 2 * 3600                        # fin de la session (15 h)
    assert detail["resets_at"].startswith("2026-10-17T15:00:00")
    assert e.value.headers["Retry-After"] == str(2 * 3600)
    assert detail["quota"]["messages_used"] == 3                   # le jour n'a pas bougé
    horloge.avancer(hours=2, minutes=1)                            # 15 h 01 : session expirée
    q = await svc.reserve(USER)
    assert q.session.started_at == DEBUT + timedelta(hours=5, minutes=1)
    assert q.session.messages_used == 1 and q.messages_used == 4   # nouvelle session, jour conservé
    assert len(supa.sessions) == 2


async def test_limite_de_tokens_de_session(redis, horloge):
    supa = SupabaseAbo(horloge)
    svc = service(redis, supa)
    q = await svc.reserve(USER)
    await svc.record_usage(reservation(q), 30_000)
    with pytest.raises(HTTPException) as e:
        await svc.reserve(USER)
    assert e.value.detail["kind"] == "session_tokens"


async def test_jour_epuise_n_ouvre_aucune_session(redis, horloge):
    supa = SupabaseAbo(horloge, plan="free")
    supa.jour = (100, 0)
    with pytest.raises(HTTPException) as e:
        await service(redis, supa).reserve(USER)
    assert e.value.detail["kind"] == "messages" and supa.sessions == []


async def test_application_fermee_ou_backend_redemarre_meme_session(redis, horloge):
    supa = SupabaseAbo(horloge)
    svc = service(redis, supa)
    q = await svc.reserve(USER)
    await svc.record_usage(reservation(q), 1_000)
    await redis.flushall()                          # redémarrage de Redis / du backend
    horloge.avancer(hours=1)
    q2 = await service(redis, supa).reserve(USER)   # nouvelle instance (autre appareil, même compte)
    assert q2.session.id == q.session.id
    assert (q2.session.messages_used, q2.session.tokens_used) == (2, 1_000)   # réhydraté depuis la base
    assert (q2.messages_used, q2.tokens_used) == (2, 1_000)


async def test_appareils_differents_meme_consommation(redis, horloge):
    supa = SupabaseAbo(horloge)
    android, windows, web = service(redis, supa), service(redis, supa), service(redis, supa)
    a = await android.reserve(USER)
    b = await windows.reserve(USER)
    c = await web.reserve(USER)
    assert a.session.id == b.session.id == c.session.id and c.session.messages_used == 3


async def test_appels_simultanes_ne_depassent_pas_la_session(redis, horloge):
    supa = SupabaseAbo(horloge)                     # 50 par session, 200 par jour
    svc = service(redis, supa)

    async def un_appel():
        try:
            await svc.reserve(USER)
            return True
        except HTTPException:
            return False

    resultats = await asyncio.gather(*(un_appel() for _ in range(80)))
    assert sum(resultats) == 50 and len(supa.sessions) == 1
    assert await redis.get(requests_key(USER, DEBUT.date())) == "50"


async def test_release_rend_le_jour_et_la_session(redis, horloge):
    supa = SupabaseAbo(horloge)
    svc = service(redis, supa)
    q = await svc.reserve(USER)
    await svc.release(reservation(q))
    q2 = await svc.reserve(USER)
    assert (q2.messages_used, q2.session.messages_used) == (1, 1)


async def test_duree_modifiee_vaut_pour_les_nouvelles_sessions(redis, horloge):
    supa = SupabaseAbo(horloge)
    svc = service(redis, supa)
    q = await svc.reserve(USER)
    supa.offres["pro"]["session_duration_minutes"] = 360
    await svc.invalidate_limits(USER)
    assert (await svc.reserve(USER)).session.ends_at == q.session.ends_at     # session en cours inchangée
    horloge.avancer(hours=5, seconds=1)
    assert (await svc.reserve(USER)).session.duration_minutes == 360


async def test_comptabilisation_unique_jour_session_et_fournisseur(redis, horloge):
    """Une requête composée (réponse + lots de propositions) est comptée une fois."""
    supa = SupabaseAbo(horloge)
    svc = service(redis, supa)
    q = await svc.reserve(USER)
    await svc.record_usage(reservation(q), 4_000, tokens_input=3_100, tokens_output=900,
                           provider="anthropic", model="claude-opus-5-5")
    assert supa.increments == [(1, 4_000)]
    assert (supa.sessions[0]["messages_used"], supa.sessions[0]["tokens_used"]) == (1, 4_000)
    assert supa.llm == [("anthropic", "claude-opus-5-5", 1, 3_100, 900)]
    statut = await svc.get_status(USER)
    assert (statut.tokens_used, statut.session.tokens_used) == (4_000, 4_000)


async def test_suivi_par_fournisseur_jamais_bloquant(redis, horloge):
    supa = SupabaseAbo(horloge)

    async def panne(*args, **kwargs):
        raise RuntimeError("table absente")

    supa.increment_llm_usage = panne
    svc = service(redis, supa)
    q = await svc.reserve(USER)
    await svc.record_usage(reservation(q), 10, provider="groq", model="m")
    assert supa.increments == [(1, 10)]


# --- Routage MIA selon l'abonnement -------------------------------------------------

def requete(entetes: dict | None = None) -> Request:
    return Request({"type": "http", "headers": [(k.lower().encode(), v.encode()) for k, v in (entetes or {}).items()]})


@pytest.fixture
def choix(monkeypatch):
    demandes = []

    def fournisseur(nom=None, settings=None, modele=None):
        demandes.append((nom, modele))
        return SimpleNamespace(nom=nom or "anthropic", modele=modele)

    monkeypatch.setattr(chat.selection, "fournisseur", fournisseur)
    return demandes


async def routage(redis, horloge, plan, choix, entetes=None, **reglages):
    svc = service(redis, SupabaseAbo(horloge, plan=plan))
    s = settings.model_copy(update={"abonnements_routage": True, **reglages})
    return await chat.get_fournisseur(requete(entetes), AuthUser(USER, None, "authenticated"), s, svc)


async def test_free_vers_groq_et_pro_vers_claude(redis, horloge, choix):
    await routage(redis, horloge, "free", choix)
    await redis.flushall()
    await routage(redis, horloge, "pro", choix)
    assert choix == [("groq", "openai/gpt-oss-120b"), ("anthropic", "claude-opus-5-5")]


async def test_un_compte_free_ne_contourne_pas_son_offre(redis, horloge, choix):
    with pytest.raises(HTTPException) as e:
        await routage(redis, horloge, "free", choix, {"X-Jarvis-Fournisseur": "anthropic"})
    assert e.value.status_code == 403 and choix == []
    # Même en environnement de test, hors LLM_ADMINS.
    with pytest.raises(HTTPException):
        await routage(redis, horloge, "free", choix, {"X-Jarvis-Fournisseur": "anthropic"},
                      environnement="development", llm_selection_manuelle=True)
    assert choix == []


async def test_admin_de_test_garde_le_choix_manuel(redis, horloge, choix):
    await routage(redis, horloge, "free", choix, {"X-Jarvis-Fournisseur": "anthropic"},
                  environnement="development", llm_selection_manuelle=True, llm_admins=[USER])
    assert choix == [("anthropic", None)]


async def test_routage_desactive_comportement_actuel(redis, horloge, choix):
    svc = service(redis, SupabaseAbo(horloge, plan="free"))
    s = settings.model_copy(update={"abonnements_routage": False})
    await chat.get_fournisseur(requete(), AuthUser(USER, None, "authenticated"), s, svc)
    assert choix == [(None, None)]                  # LLM_PROVIDER pour tous


async def test_fournisseur_de_l_offre_non_configure_sans_repli(redis, horloge, monkeypatch):
    def absent(nom=None, settings=None, modele=None):
        raise FournisseurNonConfigure("Fournisseur « groq » non configuré : OPENAI_API_KEY manquant.")

    monkeypatch.setattr(chat.selection, "fournisseur", absent)
    with pytest.raises(HTTPException) as e:
        await routage(redis, horloge, "free", [])
    assert e.value.status_code == 503 and e.value.detail["code"] == "llm_config"


# --- Route de chat et /me/quota -----------------------------------------------------

@pytest.fixture
def appli(redis, horloge):
    supa = SupabaseAbo(horloge)
    svc = service(redis, supa)
    app = FastAPI()
    app.include_router(chat.router, prefix="/api/v1")
    from app.main import my_quota
    app.add_api_route("/me/quota", my_quota)
    e = SimpleNamespace(supa=supa, svc=svc, llm=FakeOpenAI())
    app.dependency_overrides[get_quota_service] = lambda: svc
    app.dependency_overrides[get_supabase] = lambda: supa
    app.dependency_overrides[get_redis] = lambda: redis
    app.dependency_overrides[chat.get_fournisseur] = lambda: fournisseur_test(e.llm)
    e.client = httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test")
    return e


async def test_chat_compte_dans_le_jour_la_session_et_par_fournisseur(appli):
    r = await appli.client.post("/api/v1/chat/stream", json={"message": "Bonjour"}, headers=auth_headers())
    await chat.wait_background_tasks()
    assert [e for e, _ in parse_sse(r.text)][-1] == "done"
    s = appli.supa.sessions[0]
    assert (s["messages_used"], s["tokens_used"]) == (1, 46)       # 40 + 6 (FakeOpenAI)
    assert appli.supa.llm == [("groq", settings.openai_model, 1, 40, 6)]


async def test_demande_trop_grosse_refusee_avant_l_appel(appli):
    appli.supa.offres["pro"]["session_token_limit"] = 50
    r = await appli.client.post("/api/v1/chat/stream", json={"message": "x" * 2_000}, headers=auth_headers())
    assert r.status_code == 429 and r.json()["detail"]["kind"] == "session_tokens"
    assert appli.llm.calls == []                                   # aucun appel facturable
    q = await appli.svc.get_status(USER)
    assert q.messages_used == 0 and q.session.messages_used == 0   # requête rendue


async def test_me_quota_pour_les_jauges(appli):
    await appli.client.post("/api/v1/chat/stream", json={"message": "Bonjour"}, headers=auth_headers())
    await chat.wait_background_tasks()
    d = (await appli.client.get("/me/quota", headers=auth_headers())).json()
    assert d["plan"] == "pro" and d["llm_provider"] == "anthropic" and d["llm_model"] == "claude-opus-5-5"
    assert (d["messages_used"], d["messages_limit"], d["tokens_limit"]) == (1, 200, 100_000)
    assert d["resets_at"].startswith("2026-10-18T00:00:00") and d["critical_threshold_percent"] == 80
    s = d["session"]
    assert s["active"] and s["duration_minutes"] == 300 and s["ends_at"].startswith("2026-10-17T15:00:00")
    assert (s["messages_used"], s["messages_limit"], s["tokens_used"], s["tokens_limit"]) == (1, 50, 46, 30_000)
    assert d["fournisseur_actif"]["routage_abonnement"] is False
    assert d["exception"] is False


async def test_me_quota_sans_session_n_en_ouvre_pas(appli):
    d = (await appli.client.get("/me/quota", headers=auth_headers())).json()
    assert d["session"]["active"] is False and d["session"]["duration_minutes"] == 300
    assert d["session"]["messages_limit"] == 50 and appli.supa.sessions == []
