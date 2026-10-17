"""MIA universel : choix du fournisseur (app/llm/selection.py)."""

import pytest

from app.config import Settings
from app.llm import selection
from app.llm.anthropic import FournisseurAnthropic
from app.llm.groq import BASE_GROQ, FournisseurGroq
from app.llm.selection import FournisseurInconnu, FournisseurNonConfigure, configures, creer

CLE_ANTHROPIC = "cle-anthropic-de-test"


def reglages(**valeurs) -> Settings:
    base = dict(
        supabase_url="https://test.supabase.co", supabase_service_role_key="srv",
        openai_api_key="gsk_test", openai_base_url=None, openai_model="openai/gpt-oss-120b",
        anthropic_api_key=CLE_ANTHROPIC, anthropic_model="claude-modele-configure", anthropic_effort=None,
    )
    base.update(valeurs)
    return Settings(_env_file=None, **base)


def test_anthropic_par_defaut():
    assert Settings.model_fields["llm_provider"].default == "anthropic"
    f = creer(settings=reglages())
    assert isinstance(f, FournisseurAnthropic)
    assert f.modele == "claude-modele-configure"      # pris dans la configuration
    assert f.effort is None


def test_effort_de_la_configuration():
    assert creer(settings=reglages(anthropic_effort=" Medium ")).effort == "medium"
    with pytest.raises(FournisseurNonConfigure, match="ANTHROPIC_EFFORT"):
        creer(settings=reglages(anthropic_effort="turbo"))


def test_groq_conserve_et_selectionnable_explicitement():
    f = creer("groq", settings=reglages())
    assert isinstance(f, FournisseurGroq)
    assert f.modele == "openai/gpt-oss-120b"
    assert str(f._client.base_url).startswith(BASE_GROQ)


def test_selection_par_configuration_et_casse_ignoree():
    assert isinstance(creer(settings=reglages(llm_provider=" GROQ ")), FournisseurGroq)
    assert isinstance(creer(" Anthropic ", settings=reglages(llm_provider="groq")), FournisseurAnthropic)
    assert isinstance(creer(settings=reglages(llm_provider="")), FournisseurAnthropic)


def test_fournisseur_inconnu_signale():
    with pytest.raises(FournisseurInconnu, match="anthropic, groq"):
        creer("gemini", settings=reglages())
    with pytest.raises(FournisseurInconnu):
        creer(settings=reglages(llm_provider="mistral"))


@pytest.mark.parametrize("valeurs,variable", [
    ({"anthropic_api_key": None}, "ANTHROPIC_API_KEY"),
    ({"anthropic_api_key": "   "}, "ANTHROPIC_API_KEY"),
    ({"anthropic_model": None}, "ANTHROPIC_MODEL"),
])
def test_anthropic_non_configure_sans_repli_vers_groq(valeurs, variable):
    with pytest.raises(FournisseurNonConfigure) as e:
        creer(settings=reglages(**valeurs))
    assert variable in str(e.value)
    assert CLE_ANTHROPIC not in str(e.value)          # jamais une valeur secrète


def test_groq_non_configure():
    with pytest.raises(FournisseurNonConfigure, match="OPENAI_MODEL"):
        creer("groq", settings=reglages(openai_model=""))


def test_etat_des_fournisseurs():
    assert configures(reglages()) == {"anthropic": True, "groq": True}
    assert configures(reglages(anthropic_api_key=None)) == {"anthropic": False, "groq": True}


async def test_instance_unique_par_fournisseur(monkeypatch):
    monkeypatch.setattr(selection, "get_settings", lambda: reglages())
    monkeypatch.setattr(selection, "_instances", {})
    a = selection.fournisseur()
    assert a is selection.fournisseur("anthropic") and isinstance(a, FournisseurAnthropic)
    g = selection.fournisseur("groq")
    assert g is not a
    await selection.fermer_tous()
    assert selection._instances == {}
