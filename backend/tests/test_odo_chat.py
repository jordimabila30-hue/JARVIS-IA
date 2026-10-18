"""ODO dans la route de chat et la confirmation des actions, avec Claude et
GroqCloud simulés (vrais SDK, transport HTTP simulé). Aucun appel réel.
"""

import json
import time

import httpx
import jwt
import pytest
import pytest_asyncio
from fastapi import FastAPI

from app.api.v1 import chat, odo as route_odo
from app.config import get_settings
from app.odo.outils_fictifs import ActionFictive
from app.odo.registre import RegistreOutils
from app.odo.outils_fictifs import outils_fictifs
from app.odo.service import ServiceODO, get_odo
from app.quota import QuotaService, get_quota_service, requests_key, utc_now
from app.redis_client import get_redis
from app.supabase_client import UserLimits, get_supabase
from faux_llm import SERVEURS, Scenario
from test_chat import USER, FakeSupabase, auth_headers, parse_sse

settings = get_settings()
AUTRE = "99999999-9999-9999-9999-999999999999"


def evenements(raw: str):
    return parse_sse("\n\n".join(b for b in raw.split("\n\n") if b.strip() and not b.startswith(":")))


def jeton(user: str) -> dict:
    token = jwt.encode({"sub": user, "role": "authenticated", "aud": "authenticated",
                        "iss": settings.supabase_issuer, "exp": int(time.time()) + 3600},
                       settings.supabase_jwt_secret, algorithm="HS256")
    return {"Authorization": f"Bearer {token}"}


@pytest_asyncio.fixture
async def env(redis):
    supa = FakeSupabase(limits=UserLimits("free", 30, 50_000))
    service = QuotaService(redis, supa)
    app = FastAPI()
    app.include_router(chat.router, prefix="/api/v1")
    app.include_router(route_odo.router, prefix="/api/v1")
    reglages = {"odo_actif": True}
    e = None

    def odo():
        s = settings.model_copy(update={"environnement": "development", "odo_outils_fictifs": True, **reglages})
        return ServiceODO(s, redis, registre=RegistreOutils(outils_fictifs()))

    app.dependency_overrides[get_quota_service] = lambda: service
    app.dependency_overrides[get_supabase] = lambda: supa
    app.dependency_overrides[get_redis] = lambda: redis
    app.dependency_overrides[get_odo] = odo
    app.dependency_overrides[chat.get_fournisseur] = lambda: e.llm
    client = httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test")
    from types import SimpleNamespace
    e = SimpleNamespace(client=client, redis=redis, supa=supa, svc=service, llm=None, reglages=reglages)
    ActionFictive.executions.clear()
    yield e
    await client.aclose()


async def chat_post(env, message="Quel temps fait-il ?", user=USER):
    r = await env.client.post("/api/v1/chat/stream", json={"message": message}, headers=jeton(user))
    await chat.wait_background_tasks()
    return r


def scenario_outil(**k) -> Scenario:
    return Scenario(**{"textes": ["Je regarde."], "entree": 100, "sortie": 20,
                       "appels": [("appel_1", "lecture_fictive", {"fiche": "meteo"})], **k})


@pytest.mark.parametrize("nom", ["anthropic", "groq"])
async def test_demande_multi_tours_un_message_tokens_additionnes(env, nom):
    serveur = SERVEURS[nom](Scenario(textes=["Il fait 18 °C."], entree=150, sortie=30), etapes=[scenario_outil()])
    env.llm = serveur.fournisseur()
    r = await chat_post(env)
    ev = evenements(r.text)
    noms = [e for e, _ in ev]
    assert noms[0] == "meta" and noms[-1] == "done"
    assert [d for e, d in ev if e == "outil"] == [{"nom": "lecture_fictive", "etat": "en_cours", "code": None},
                                                  {"nom": "lecture_fictive", "etat": "termine", "code": None}]
    assert "".join(d["text"] for e, d in ev if e == "delta") == "Je regarde.\n\nIl fait 18 °C."
    assert len(serveur.requetes) == 2                               # 2 tours du modèle
    # UN message compté, tokens des deux tours additionnés (cache Claude compris).
    total = ev[-1][1]["usage"]["total_tokens"]
    attendu = (100 + 150 + 2 * (5 if nom == "anthropic" else 0)) + 20 + 30
    assert total == attendu
    assert env.supa.increments == [(1, attendu)]
    assert await env.redis.get(requests_key(USER, utc_now().date())) == "1"
    [reponse] = [x for x in env.supa.inserted if x["role"] == "assistant"]
    assert reponse["content"] == "Je regarde.\n\nIl fait 18 °C." and reponse["model"] == "modele-servi"


@pytest.mark.parametrize("nom", ["anthropic", "groq"])
async def test_odo_desactive_chat_strictement_inchange(env, nom):
    env.reglages["odo_actif"] = False
    serveur = SERVEURS[nom](Scenario())
    env.llm = serveur.fournisseur()
    ev = evenements((await chat_post(env)).text)
    assert {e for e, _ in ev} == {"meta", "delta", "done"}
    assert "tools" not in serveur.requetes[0] and len(serveur.requetes) == 1
    sys_msg = serveur.requetes[0].get("system") or serveur.requetes[0]["messages"][0]["content"]
    assert "resultat_outil" not in sys_msg                          # aucune consigne d'outils


async def test_action_sensible_puis_confirmation_unique(env):
    serveur = SERVEURS["anthropic"](Scenario(textes=["Confirme l'action dans JARVIS."]), etapes=[
        Scenario(textes=[], appels=[("a1", "action_fictive", {"cible": "rapport"})])])
    env.llm = serveur.fournisseur()
    ev = evenements((await chat_post(env, "Lance l'action sur le rapport")).text)
    [conf] = [d for e, d in ev if e == "confirmation"]
    assert conf["outil"] == "action_fictive" and "rapport" in conf["resume"] and conf["expire_at"]
    assert ActionFictive.executions == []                            # jamais exécutée pendant le chat
    [reponse] = [x for x in env.supa.inserted if x["role"] == "assistant"]
    assert reponse["attachments"] == [{"type": "odo_confirmation", **conf}]

    url = f"/api/v1/odo/confirmations/{conf['id']}"
    autre = await env.client.post(url, json={"decision": "confirmer"}, headers=jeton(AUTRE))
    assert autre.status_code == 410 and ActionFictive.executions == []        # autre compte
    ok = await env.client.post(url, json={"decision": "confirmer"}, headers=jeton(USER))
    assert ok.status_code == 200 and ok.json()["statut"] == "executee"
    assert ActionFictive.executions == [(USER, "rapport")]
    encore = await env.client.post(url, json={"decision": "confirmer"}, headers=jeton(USER))
    assert encore.status_code == 410 and len(ActionFictive.executions) == 1    # au plus une fois
    # Aucun quota de tokens consommé par la confirmation.
    assert env.supa.increments == [(1, env.supa.increments[0][1])]


async def test_confirmation_refusee_ou_sans_odo(env):
    serveur = SERVEURS["groq"](Scenario(textes=["D'accord."]), etapes=[
        Scenario(textes=[], appels=[("a1", "action_fictive", {"cible": "x"})])])
    env.llm = serveur.fournisseur()
    [conf] = [d for e, d in evenements((await chat_post(env)).text) if e == "confirmation"]
    r = await env.client.post(f"/api/v1/odo/confirmations/{conf['id']}", json={"decision": "refuser"},
                              headers=jeton(USER))
    assert r.json()["statut"] == "refusee" and ActionFictive.executions == []
    env.reglages["odo_actif"] = False
    r = await env.client.post("/api/v1/odo/confirmations/abcdefghij", json={"decision": "confirmer"},
                              headers=jeton(USER))
    assert r.status_code == 404
    r = await env.client.post("/api/v1/odo/confirmations/abcdefghij", json={"decision": "confirmer"})
    assert r.status_code == 401                                      # authentification obligatoire


async def test_budget_du_jour_epuise_entre_deux_tours(env):
    env.supa.limits = UserLimits("free", 30, 400)                    # 400 tokens dans la journée
    serveur = SERVEURS["anthropic"](etapes=[scenario_outil(entree=380, sortie=20)])
    env.llm = serveur.fournisseur()
    ev = evenements((await chat_post(env)).text)
    assert ev[-1][0] == "error" and ev[-1][1]["code"] == "llm_budget"
    assert len(serveur.requetes) == 1                                # 2e appel facturable évité
    [(messages, tokens)] = env.supa.increments
    assert messages == 1 and tokens >= 400                           # le tour consommé est compté


async def test_outils_injectes_jamais_suivis_dans_la_route(env):
    serveur = SERVEURS["anthropic"](Scenario(textes=["Voici les documents."]), etapes=[
        Scenario(textes=[], appels=[("a1", "recherche_fictive", {"requete": "contrat"})])])
    env.llm = serveur.fournisseur()
    await chat_post(env)
    resultat = serveur.requetes[1]["messages"][-1]["content"][0]["content"]
    assert resultat.count("</resultat_outil>") == 1 and "<consignes_systeme>" not in resultat
    assert ActionFictive.executions == []


def test_attachment_inconnu_ignore_par_les_lecteurs_existants():
    from app.comprehension import propositions, restauration
    pieces = [{"type": "odo_confirmation", "id": "x", "outil": "action_fictive"}]
    assert restauration.references(pieces) == [] if hasattr(restauration, "references") else True
    assert propositions.lues(pieces, "m") is None
    assert json.dumps(pieces)
