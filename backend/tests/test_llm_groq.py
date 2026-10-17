"""MIA universel : adaptateur GroqCloud (comportement de production conservé)."""

import pytest

from app.llm import LimiteDebit, Texte
from app.llm.groq import BASE_GROQ, FournisseurGroq, adresse
from faux_llm import Journal, Scenario, fournisseur_groq

MESSAGES = [
    {"role": "system", "content": "S"},
    {"role": "user", "content": "Q"},
    {"role": "system", "content": "Rappel"},
    {"role": "user", "content": "Q2"},
]


def test_adresse_identique_a_get_openai():
    assert adresse("gsk_abc", None) == BASE_GROQ
    assert adresse("sk-abc", None) is None                       # OpenAI
    assert adresse("gsk_abc", "http://proxy/v1") == "http://proxy/v1"


def test_client_reel_pointe_sur_groq_sans_nouvel_essai():
    f = FournisseurGroq(cle="gsk_test", modele="openai/gpt-oss-120b")
    assert str(f._client.base_url).startswith(BASE_GROQ)
    assert f._client.max_retries == 0
    with pytest.raises(ValueError):
        FournisseurGroq(cle="", modele="m")


async def test_flux_format_openai_inchange():
    journal = Journal()
    f = fournisseur_groq(Scenario(), journal)
    ev = [e async for e in f.flux(MESSAGES, max_sortie=1024)]
    r = journal.requetes[0]
    assert r["messages"] == MESSAGES                 # rôles system gardés tels quels
    assert r["stream"] is True and r["stream_options"] == {"include_usage": True}
    assert r["max_tokens"] == 1024 and r["model"] == "openai/gpt-oss-120b"
    assert "reasoning_effort" not in r               # flux principal : comme en production
    assert "".join(e.texte for e in ev if isinstance(e, Texte)) == "Bonjour Tony."


async def test_effort_seulement_pour_gpt_oss():
    journal = Journal()
    f = fournisseur_groq(Scenario(), journal)
    _ = [e async for e in f.flux(MESSAGES, max_sortie=10, effort="xhigh")]
    assert journal.requetes[0]["reasoning_effort"] == "high"

    journal = Journal()
    f = fournisseur_groq(Scenario(), journal, modele="qwen/qwen3.8-27b")
    _ = [e async for e in f.flux(MESSAGES, max_sortie=10, effort="high")]
    assert "reasoning_effort" not in journal.requetes[0]


async def test_json_mode_json_et_raisonnement_court_comme_appel_lot():
    journal = Journal()
    f = fournisseur_groq(Scenario(json_texte='{"a": 1}'), journal)
    r = await f.json(MESSAGES, max_sortie=2600)
    req = journal.requetes[0]
    assert req["response_format"] == {"type": "json_object"}
    assert req["reasoning_effort"] == "low" and req["max_tokens"] == 2600
    assert "stream" not in req
    assert r.donnees == {"a": 1}


async def test_json_mode_refuse_puis_texte_relu_et_memorise():
    journal = Journal()
    f = fournisseur_groq(Scenario(json_texte='{"a": 1}'), journal, refuser_json=True)
    assert (await f.json(MESSAGES, max_sortie=100)).donnees == {"a": 1}
    assert ["response_format" in r for r in journal.requetes] == [True, False]
    await f.json(MESSAGES, max_sortie=100)
    assert ["response_format" in r for r in journal.requetes] == [True, False, False]


async def test_usage_absent_estime():
    f = fournisseur_groq(Scenario(usage_absent=True))
    fin = [e async for e in f.flux(MESSAGES, max_sortie=10)][-1]
    assert fin.usage.estime and fin.usage.entree > 0 and fin.usage.sortie > 0


async def _limite(corps, entetes=None) -> LimiteDebit:
    f = fournisseur_groq(Scenario(statut=429, corps_erreur=corps, entetes=entetes or {}))
    with pytest.raises(LimiteDebit) as e:
        _ = [x async for x in f.flux(MESSAGES, max_sortie=10)]
    return e.value


async def test_delai_groq_lu_dans_x_ratelimit():
    e = await _limite({"error": {"message": "Rate limit reached", "code": "rate_limit_exceeded"}},
                      {"x-ratelimit-reset-tokens": "7.66s"})
    assert e.attente == pytest.approx(8.16)


async def test_quota_quotidien_groq_sans_attente():
    e = await _limite({"error": {"message": "Rate limit reached on tokens per day (TPD)",
                                 "code": "rate_limit_exceeded"}}, {"retry-after": "120"})
    assert e.code == "llm_daily_quota" and e.attente is None
    assert "2 minutes" in e.message


async def test_credit_epuise_sans_attente():
    e = await _limite({"error": {"message": "You exceeded your current quota", "code": "insufficient_quota"}})
    assert e.code == "llm_credit" and e.attente is None
