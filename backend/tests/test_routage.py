"""Routage Free / Pro de bout en bout : vraie dépendance `get_fournisseur`,
vraie route de chat (flux SSE), /me/quota, quotas quotidiens, avec Claude
et GroqCloud simulés (vrais SDK, transport simulé). Aucun appel réel.

Les fournisseurs et modèles viennent de `plan_config` (faux Supabase) :
rien n'est codé en dur côté backend.
"""

from types import SimpleNamespace

import httpx
import pytest
import pytest_asyncio
from fastapi import FastAPI

from app.api.v1 import chat
from app.config import get_settings
from app.llm import FournisseurNonConfigure
from app.main import my_quota
from app.odo.outils_fictifs import outils_fictifs
from app.odo.registre import RegistreOutils
from app.odo.service import ServiceODO, get_odo
from app.quota import QuotaService, get_quota_service, limits_key
from app.redis_client import get_redis
from app.supabase_client import get_supabase
from faux_llm import Scenario, ServeurClaude, ServeurGroq
from test_abonnements import Horloge, SupabaseAbo
from test_chat import USER, auth_headers, parse_sse

settings = get_settings()


def evenements(raw: str):
    return parse_sse("\n\n".join(b for b in raw.split("\n\n") if b.strip() and not b.startswith(":")))


@pytest_asyncio.fixture
async def appli(redis, monkeypatch):
    supa = SupabaseAbo(Horloge(), plan="free")
    for offre in supa.offres.values():          # quotas quotidiens seulement (sessions vidées)
        offre.update(session_duration_minutes=None, session_message_limit=None, session_token_limit=None)
    svc = QuotaService(redis, supa, limits_cache_ttl=30)
    serveurs = {"anthropic": ServeurClaude(Scenario(textes=["Réponse de Claude."])),
                "groq": ServeurGroq(Scenario(textes=["Réponse de Groq."]))}
    choisis = []
    absents = set()

    def fournisseur(nom=None, settings=None, modele=None):
        nom = nom or "anthropic"                    # LLM_PROVIDER (fournisseur global)
        if nom in absents:
            raise FournisseurNonConfigure(f"Fournisseur « {nom} » non configuré : variable manquante.")
        choisis.append((nom, modele))
        return serveurs[nom].fournisseur(**({"modele": modele} if modele else {}))

    monkeypatch.setattr(chat.selection, "fournisseur", fournisseur)
    reglages = {"abonnements_routage": True}
    app = FastAPI()
    app.include_router(chat.router, prefix="/api/v1")
    app.add_api_route("/me/quota", my_quota)
    app.dependency_overrides[get_settings] = lambda: settings.model_copy(update=reglages)
    app.dependency_overrides[get_quota_service] = lambda: svc
    app.dependency_overrides[get_supabase] = lambda: supa
    app.dependency_overrides[get_redis] = lambda: redis
    client = httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test")
    e = SimpleNamespace(client=client, supa=supa, svc=svc, redis=redis, serveurs=serveurs, choisis=choisis,
                        absents=absents, reglages=reglages, app=app)
    yield e
    await client.aclose()


async def chat_post(appli, entetes=None, **corps):
    r = await appli.client.post("/api/v1/chat/stream", json={"message": "Bonjour", **corps},
                                headers={**auth_headers(), **(entetes or {})})
    await chat.wait_background_tasks()
    return r


def servi(appli, r) -> tuple[str, str]:
    """(fournisseur de l'en-tête, modèle demandé au faux serveur)."""
    nom = r.headers["x-jarvis-fournisseur"]
    return nom, appli.serveurs[nom].requetes[-1]["model"]


async def expirer_cache(appli):
    await appli.redis.delete(limits_key(USER))          # TTL de 30 s écoulé


async def test_free_groq_et_pro_claude_en_streaming(appli):
    r = await chat_post(appli)
    ev = evenements(r.text)
    assert servi(appli, r) == ("groq", "openai/gpt-oss-120b")
    assert "".join(d["text"] for e, d in ev if e == "delta") == "Réponse de Groq." and ev[-1][0] == "done"
    assert appli.serveurs["anthropic"].requetes == []
    appli.supa.compte["plan"] = "pro"
    await expirer_cache(appli)
    r = await chat_post(appli)
    ev = evenements(r.text)
    assert servi(appli, r) == ("anthropic", "claude-opus-5-5")
    assert "".join(d["text"] for e, d in ev if e == "delta") == "Réponse de Claude." and ev[-1][0] == "done"


async def test_changement_d_abonnement_apres_le_cache_sans_redemarrage(appli):
    await chat_post(appli)                                          # Free → GroqCloud
    appli.supa.compte["plan"] = "pro"                               # Free → Pro dans Supabase
    r = await chat_post(appli)
    assert servi(appli, r)[0] == "groq"                             # encore en cache (≤ 30 s)
    await expirer_cache(appli)
    r = await chat_post(appli)
    assert servi(appli, r)[0] == "anthropic"
    appli.supa.compte["plan"] = "free"                              # Pro → Free
    await expirer_cache(appli)
    r = await chat_post(appli)
    assert servi(appli, r)[0] == "groq"
    # Consommation du jour inchangée par les changements d'offre : 4 demandes.
    assert [m for m, _ in appli.supa.increments] == [1, 1, 1, 1]


async def test_plan_config_modifie_fournisseur_et_modele(appli):
    appli.supa.offres["free"].update(llm_provider="groq", llm_model="openai/gpt-oss-20b")
    r = await chat_post(appli)
    assert servi(appli, r) == ("groq", "openai/gpt-oss-20b")
    appli.supa.offres["free"].update(llm_provider="anthropic", llm_model="claude-sonnet-5-5")
    await expirer_cache(appli)
    r = await chat_post(appli)
    assert servi(appli, r) == ("anthropic", "claude-sonnet-5-5")


async def test_le_client_ne_peut_pas_forcer_claude(appli):
    r = await chat_post(appli, {chat.ENTETE_FOURNISSEUR: "anthropic"})
    assert r.status_code == 403 and appli.choisis == []
    r = await chat_post(appli, llm_provider="anthropic", plan="pro", model="claude-opus-5-5")
    assert servi(appli, r) == ("groq", "openai/gpt-oss-120b")       # champs du corps ignorés
    assert appli.serveurs["anthropic"].requetes == []


async def test_fournisseur_de_l_offre_absent_erreur_sans_repli(appli):
    appli.absents.add("groq")
    r = await chat_post(appli)
    assert r.status_code == 503 and r.json()["detail"]["code"] == "llm_config"
    assert appli.serveurs["anthropic"].requetes == [] and appli.supa.increments == []
    q = await appli.svc.get_status(USER)
    assert q.messages_used == 0                                     # rien consommé


async def test_me_quota_exact_avec_le_routage(appli):
    await chat_post(appli)
    d = (await appli.client.get("/me/quota", headers=auth_headers())).json()
    assert (d["plan"], d["llm_provider"], d["llm_model"]) == ("free", "groq", "openai/gpt-oss-120b")
    assert d["fournisseur_actif"] == {"llm_provider": "groq", "llm_model": "openai/gpt-oss-120b",
                                      "routage_abonnement": True}
    assert (d["messages_used"], d["messages_limit"], d["tokens_limit"]) == (1, 100, 50_000)
    assert d["session"]["active"] is False and d["session"]["duration_minutes"] is None   # aucune session


async def test_routage_inactif_fournisseur_global_et_me_quota_le_dit(appli):
    appli.reglages["abonnements_routage"] = False
    r = await chat_post(appli)
    assert servi(appli, r)[0] == "anthropic"                        # LLM_PROVIDER pour tous
    d = (await appli.client.get("/me/quota", headers=auth_headers())).json()
    assert d["llm_provider"] == "groq"                              # offre…
    assert d["fournisseur_actif"]["llm_provider"] == "anthropic"    # … mais servi par Claude
    assert d["fournisseur_actif"]["routage_abonnement"] is False


async def test_quotas_quotidiens_toujours_appliques(appli):
    appli.supa.offres["free"]["daily_message_limit"] = 2
    await expirer_cache(appli)
    assert (await chat_post(appli)).status_code == 200
    assert (await chat_post(appli)).status_code == 200
    r = await chat_post(appli)
    assert r.status_code == 429 and r.json()["detail"]["kind"] == "messages"
    assert len(appli.serveurs["groq"].requetes) == 2                # aucun appel au-delà


@pytest.mark.parametrize("plan,nom", [("free", "groq"), ("pro", "anthropic")])
async def test_odo_utilise_le_fournisseur_selectionne(appli, plan, nom):
    appli.supa.compte["plan"] = plan
    appli.reglages.update(odo_actif=True, environnement="development", odo_outils_fictifs=True)
    appli.app.dependency_overrides[get_odo] = lambda: ServiceODO(
        settings.model_copy(update=appli.reglages), appli.redis, registre=RegistreOutils(outils_fictifs()))
    appli.serveurs[nom].etapes = [Scenario(textes=[], appels=[("a1", "lecture_fictive", {"fiche": "agenda"})])]
    r = await chat_post(appli)
    ev = evenements(r.text)
    assert ev[-1][0] == "done" and ("outil", {"nom": "lecture_fictive", "etat": "termine", "code": None}) in ev
    autre = "anthropic" if nom == "groq" else "groq"
    assert len(appli.serveurs[nom].requetes) == 2 and appli.serveurs[autre].requetes == []
