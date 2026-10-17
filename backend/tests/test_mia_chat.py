"""MIA universel, phase 2 : la route du chat (écrit et vocal : même route)
avec Claude, et le choix protégé du fournisseur.

Claude passe par le vrai SDK `anthropic` vers un faux serveur Messages API
(tests/faux_llm.py) : flux SSE, erreurs et usage réellement relus.
"""

from types import SimpleNamespace

import pytest

from app.api.v1 import chat
from app.config import get_settings
from app.llm import FournisseurInconnu, FournisseurNonConfigure
from app.quota import requests_key, utc_now
from faux_llm import Scenario, ServeurClaude
from test_chat import USER, FakeOpenAI, auth_headers, env, fournisseur_test, parse_sse, post_chat  # noqa: F401

settings = get_settings()
LIMITE = {"type": "error", "error": {"type": "rate_limit_error", "message": "slow down"}}


def evenements(raw: str):
    return parse_sse("\n\n".join(b for b in raw.split("\n\n") if b.strip() and not b.startswith(":")))


def texte(events) -> str:
    return "".join(d["text"] for e, d in events if e == "delta")


async def requetes_du_jour(env) -> str | None:
    return await env.redis.get(requests_key(USER, utc_now().date()))


def reponse_jarvis(env) -> dict:
    return [r for r in env.supa.inserted if r["role"] == "assistant"][-1]


async def _sans_attente(_):
    return None


# --- Conversation normale ---------------------------------------------------------

async def test_chat_ordinaire_avec_claude(env):
    serveur = ServeurClaude(Scenario(reflexion="PLAN INTERNE DU MODELE"))
    env.llm = serveur.fournisseur(effort="medium")
    resp = await post_chat(env, message="Bonjour JARVIS")
    events = evenements(resp.text)
    assert [e for e, _ in events][0] == "meta" and [e for e, _ in events][-1] == "done"
    assert {e for e, _ in events} == {"meta", "delta", "done"}         # contrat SSE inchangé
    assert texte(events) == "Bonjour Tony."
    assert "PLAN INTERNE" not in resp.text                             # réflexion jamais diffusée
    assert resp.headers["x-jarvis-fournisseur"] == "anthropic"

    [req] = serveur.requetes
    assert req["system"].startswith("Tu es JARVIS")
    assert req["messages"] == [{"role": "user", "content": [{"type": "text", "text": "Bonjour JARVIS"}]}]
    assert req["max_tokens"] == settings.chat_max_output_tokens + settings.llm_reflexion_marge_tokens
    assert req["output_config"] == {"effort": "medium"}
    assert "thinking" not in req and "fallbacks" not in req

    jarvis = reponse_jarvis(env)
    assert jarvis["model"] == "modele-servi"                           # modèle réellement servi
    assert jarvis["content"] == "Bonjour Tony."
    # Entrée = 12 + cache (3 lus, 2 écrits) ; sortie = 7 (réflexion comprise).
    assert (jarvis["tokens_input"], jarvis["tokens_output"]) == (17, 7)
    assert events[-1][1]["usage"]["total_tokens"] == 24
    assert env.supa.increments[-1] == (1, 24)                          # quota persistant


async def test_historique_redis_puis_suite_de_conversation(env):
    serveur = ServeurClaude()
    env.llm = serveur.fournisseur()
    meta = evenements((await post_chat(env, message="Première question")).text)[0][1]
    connue = env.supa.get_conversation

    async def get_conversation(cid, uid):      # la conversation créée par le 1er échange
        if cid == meta["conversation_id"]:
            return {"id": cid, "title": "Première question", "persona": None}
        return await connue(cid, uid)

    env.supa.get_conversation = get_conversation
    await post_chat(env, message="Et ensuite ?", conversation_id=meta["conversation_id"])
    second = serveur.requetes[1]["messages"]
    assert [m["role"] for m in second] == ["user", "assistant", "user"]
    assert second[1]["content"][0]["text"] == "Bonjour Tony."          # relu depuis le contexte court
    assert second[-1]["content"][0]["text"] == "Et ensuite ?"


# --- Réponses interrompues : jamais présentées comme terminées --------------------

@pytest.mark.parametrize("raison,code", [("refus", "llm_refus"), ("longueur", "llm_incomplet")])
async def test_refus_ou_plafond_jamais_done(env, raison, code):
    env.llm = ServeurClaude(Scenario(textes=["Je "], raison=raison)).fournisseur()
    events = evenements((await post_chat(env, message="Q")).text)
    assert [e for e, _ in events] == ["meta", "delta", "error"]
    assert events[-1][1]["code"] == code and events[-1][1]["message"]
    # Le texte reçu est gardé (comme une coupure), jamais « done ».
    assert reponse_jarvis(env)["content"] == "Je "


async def test_coupure_en_plein_flux(env):
    env.llm = ServeurClaude(Scenario(erreur_milieu=True)).fournisseur()
    events = evenements((await post_chat(env, message="Q")).text)
    assert [e for e, _ in events] == ["meta", "delta", "error"]
    assert reponse_jarvis(env)["content"] == "Bon"


async def test_limite_de_debit_attendue_puis_reponse_sans_doublon(env, monkeypatch):
    monkeypatch.setattr(chat.asyncio, "sleep", _sans_attente)
    serveur = ServeurClaude(etapes=[
        Scenario(statut=429, corps_erreur=LIMITE, entetes={"retry-after": "2"}),
        Scenario(statut=529, corps_erreur={"type": "error", "error": {"type": "overloaded_error",
                                                                      "message": "Overloaded"}}),
    ])
    env.llm = serveur.fournisseur()
    resp = await post_chat(env, message="Q")
    assert ": attente du fournisseur IA" in resp.text
    events = evenements(resp.text)
    assert texte(events) == "Bonjour Tony." and events[-1][0] == "done"
    assert len(serveur.requetes) == 3


async def test_limite_trop_longue_erreur_et_quota_rendu(env):
    env.llm = ServeurClaude(etapes=[Scenario(statut=429, corps_erreur=LIMITE,
                                             entetes={"retry-after": "90"})]).fournisseur()
    events = evenements((await post_chat(env, message="Q")).text)
    assert events[-1] == ("error", {"code": "llm_rate_limit", "message": events[-1][1]["message"]})
    assert env.supa.inserted == [] and await requetes_du_jour(env) == "0"


@pytest.mark.parametrize("statut,code", [(401, "llm_auth"), (404, "llm_model"), (500, "llm_unavailable")])
async def test_erreurs_claude_avant_tout_texte(env, statut, code):
    env.llm = ServeurClaude(etapes=[Scenario(statut=statut)]).fournisseur()
    events = evenements((await post_chat(env, message="Q")).text)
    assert [e for e, _ in events] == ["meta", "error"] and events[-1][1]["code"] == code
    assert env.supa.inserted == [] and await requetes_du_jour(env) == "0"


# --- Choix du fournisseur : protégé côté serveur ----------------------------------

@pytest.fixture
def choix(env, monkeypatch):
    """Vraie dépendance `get_fournisseur`, fournisseurs simulés par nom."""
    del env.app.dependency_overrides[chat.get_fournisseur]
    serveur = ServeurClaude()
    groq = FakeOpenAI()
    instances = {"anthropic": serveur.fournisseur(), "groq": fournisseur_test(groq)}
    demandes = []

    def fournisseur(nom=None, settings=None):
        demandes.append(nom)
        if nom not in (None, "anthropic", "groq"):
            raise FournisseurInconnu(f"Fournisseur inconnu : « {nom} »")
        return instances[nom or "anthropic"]

    monkeypatch.setattr(chat.selection, "fournisseur", fournisseur)

    def reglages(**valeurs):
        env.app.dependency_overrides[get_settings] = lambda: settings.model_copy(update=valeurs)

    return SimpleNamespace(serveur=serveur, groq=groq, demandes=demandes, reglages=reglages)


async def post_avec(env, entete: str | None, **body):
    headers = {**auth_headers(), **({chat.ENTETE_FOURNISSEUR: entete} if entete else {})}
    resp = await env.client.post("/api/v1/chat/stream", json={"message": "Q", **body}, headers=headers)
    await chat.wait_background_tasks()
    return resp


async def test_claude_par_defaut_sans_entete(env, choix):
    resp = await post_avec(env, None)
    assert resp.status_code == 200 and resp.headers["x-jarvis-fournisseur"] == "anthropic"
    assert len(choix.serveur.requetes) == 1 and choix.groq.calls == []


@pytest.mark.parametrize("valeurs", [
    {},                                                                       # réglages par défaut
    {"environnement": "development", "llm_selection_manuelle": True},         # compte non admin
    {"environnement": "production", "llm_selection_manuelle": True, "llm_admins": [USER]},
    {"environnement": "development", "llm_selection_manuelle": False, "llm_admins": [USER]},
])
async def test_choix_manuel_refuse_sans_rien_consommer(env, choix, valeurs):
    choix.reglages(**valeurs)
    resp = await post_avec(env, "groq")
    assert resp.status_code == 403 and resp.json()["detail"]["code"] == "fournisseur_interdit"
    assert choix.demandes == [] and choix.groq.calls == [] and choix.serveur.requetes == []
    assert await requetes_du_jour(env) is None                              # quota jamais réservé


async def test_choix_manuel_groq_pour_un_admin_de_test(env, choix):
    choix.reglages(environnement="development", llm_selection_manuelle=True, llm_admins=[USER])
    resp = await post_avec(env, "groq")
    assert resp.status_code == 200 and resp.headers["x-jarvis-fournisseur"] == "groq"
    assert choix.demandes == ["groq"] and len(choix.groq.calls) == 1 and choix.serveur.requetes == []
    assert reponse_jarvis(env)["model"] == settings.openai_model


async def test_fournisseur_inconnu_400(env, choix):
    choix.reglages(environnement="development", llm_selection_manuelle=True, llm_admins=[USER])
    resp = await post_avec(env, "gemini")
    assert resp.status_code == 400 and resp.json()["detail"]["code"] == "fournisseur_inconnu"
    assert await requetes_du_jour(env) is None


async def test_fournisseur_non_configure_503_sans_repli(env, choix, monkeypatch):
    def absent(nom=None, settings=None):
        raise FournisseurNonConfigure("Fournisseur « anthropic » non configuré : ANTHROPIC_API_KEY manquant.")

    monkeypatch.setattr(chat.selection, "fournisseur", absent)
    resp = await post_avec(env, None)
    assert resp.status_code == 503 and resp.json()["detail"]["code"] == "llm_config"
    assert choix.groq.calls == []                                           # aucun basculement vers Groq
    assert await requetes_du_jour(env) is None


async def test_panne_de_claude_aucun_basculement(env, choix):
    choix.serveur.etapes = [Scenario(statut=500)]
    events = evenements((await post_avec(env, None)).text)
    assert events[-1][1]["code"] == "llm_unavailable"
    assert choix.groq.calls == []
