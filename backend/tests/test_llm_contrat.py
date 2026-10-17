"""MIA universel : Claude et GroqCloud respectent le MÊME contrat (app/llm/base.py).

Chaque test tourne pour les deux adaptateurs, avec les vrais SDK et un
transport HTTP simulé (tests/faux_llm.py).
"""

import pytest

from app.llm import (
    DefinitionOutil,
    ErreurFournisseur,
    ErreurLLM,
    Fin,
    FournisseurLLM,
    LimiteDebit,
    RaisonArret,
    RequeteTropGrande,
    Texte,
)
from faux_llm import FABRIQUES, Journal, Scenario

QUESTION = [
    {"role": "system", "content": "Tu es JARVIS."},
    {"role": "user", "content": "Bonjour ?"},
]

pytestmark = pytest.mark.parametrize("nom", ["anthropic", "groq"])


async def lire(f: FournisseurLLM, messages=QUESTION, **options):
    evenements = []
    async for e in f.flux(messages, max_sortie=500, **options):
        evenements.append(e)
    return evenements


def textes(evenements) -> str:
    return "".join(e.texte for e in evenements if isinstance(e, Texte))


async def test_flux_normal_texte_puis_une_seule_fin(nom):
    f = FABRIQUES[nom](Scenario())
    ev = await lire(f)
    assert isinstance(f, FournisseurLLM)
    assert textes(ev) == "Bonjour Tony."
    fins = [e for e in ev if isinstance(e, Fin)]
    assert len(fins) == 1 and ev[-1] is fins[0]
    assert fins[0].raison is RaisonArret.FIN
    assert fins[0].modele == "modele-servi"          # modèle réellement servi
    assert fins[0].usage.entree == 12 and fins[0].usage.sortie == 7
    assert not fins[0].usage.estime
    await f.fermer()


async def test_reflexion_interne_jamais_diffusee(nom):
    f = FABRIQUES[nom](Scenario(reflexion="PLAN SECRET DU MODELE"))
    ev = await lire(f)
    assert all(isinstance(e, (Texte, Fin)) for e in ev)
    assert "SECRET" not in textes(ev)
    assert all("SECRET" not in (e.detail or "") for e in ev if isinstance(e, Fin))


async def test_plafond_de_sortie_atteint(nom):
    ev = await lire(FABRIQUES[nom](Scenario(raison="longueur")))
    assert ev[-1].raison is RaisonArret.LONGUEUR
    assert textes(ev) == "Bonjour Tony."


async def test_refus_en_flux_texte_partiel_garde_et_raison_refus(nom):
    ev = await lire(FABRIQUES[nom](Scenario(textes=["Je "], raison="refus")))
    assert textes(ev) == "Je "
    assert ev[-1].raison is RaisonArret.REFUS


async def test_coupure_en_plein_flux_apres_du_texte(nom):
    f = FABRIQUES[nom](Scenario(erreur_milieu=True))
    recus = []
    with pytest.raises(ErreurLLM) as e:
        async for ev in f.flux(QUESTION, max_sortie=500):
            recus.append(ev)
    assert textes(recus) == "Bon"           # le texte reçu reste à l'appelant
    assert not any(isinstance(x, Fin) for x in recus)
    assert e.value.apres_texte is True
    assert e.value.fournisseur == nom


async def test_limite_de_debit_avant_tout_texte(nom):
    corps = ({"type": "error", "error": {"type": "rate_limit_error", "message": "slow down"}}
             if nom == "anthropic" else {"error": {"message": "Rate limit reached", "code": "rate_limit_exceeded"}})
    f = FABRIQUES[nom](Scenario(statut=429, corps_erreur=corps, entetes={"retry-after": "3"}))
    with pytest.raises(LimiteDebit) as e:
        await lire(f)
    assert e.value.attente == pytest.approx(3.5)
    assert e.value.apres_texte is False
    assert e.value.evenement() == {"code": "llm_rate_limit", "message": e.value.message}


async def test_limite_de_debit_sans_delai_annonce(nom):
    f = FABRIQUES[nom](Scenario(statut=429))
    with pytest.raises(LimiteDebit) as e:
        await lire(f)
    assert e.value.attente == 8.0


@pytest.mark.parametrize("statut,classe,code", [
    (413, RequeteTropGrande, "llm_too_large"),
    (401, ErreurFournisseur, "llm_auth"),
    (404, ErreurFournisseur, "llm_model"),
    (500, ErreurFournisseur, "llm_unavailable"),
])
async def test_erreurs_http_normalisees(nom, statut, classe, code):
    f = FABRIQUES[nom](Scenario(statut=statut))
    with pytest.raises(classe) as e:
        await lire(f)
    assert e.value.code == code and e.value.statut == statut
    assert e.value.message          # message prêt pour l'événement SSE `error`


async def test_erreurs_aussi_normalisees_en_json(nom):
    f = FABRIQUES[nom](Scenario(statut=413))
    with pytest.raises(RequeteTropGrande):
        await f.json(QUESTION, max_sortie=500)


async def test_json_valide(nom):
    f = FABRIQUES[nom](Scenario(json_texte='{"tons": [{"nom": "Naturel"}]}'))
    r = await f.json(QUESTION, max_sortie=800)
    assert r.donnees == {"tons": [{"nom": "Naturel"}]}
    assert r.raison is RaisonArret.FIN
    assert r.modele == "modele-servi"
    assert r.usage.entree == 12 and r.usage.sortie == 7


async def test_json_tolere_les_balises_de_code(nom):
    f = FABRIQUES[nom](Scenario(json_texte='Voici :\n```json\n{"a": 1}\n```'))
    assert (await f.json(QUESTION, max_sortie=800)).donnees == {"a": 1}


async def test_json_illisible_donnees_nulles_texte_garde(nom):
    f = FABRIQUES[nom](Scenario(json_texte="pas du json"))
    r = await f.json(QUESTION, max_sortie=800)
    assert r.donnees is None and r.texte == "pas du json"


async def test_json_coupe_par_le_plafond(nom):
    f = FABRIQUES[nom](Scenario(json_texte='{"a": [1, 2', raison="longueur"))
    r = await f.json(QUESTION, max_sortie=10)
    assert r.donnees is None and r.raison is RaisonArret.LONGUEUR


async def test_outils_reserves_a_odo(nom):
    f = FABRIQUES[nom](Scenario())
    with pytest.raises(NotImplementedError):
        await lire(f, outils=[DefinitionOutil("heure", "Donne l'heure", {"type": "object"})])


@pytest.mark.parametrize("messages", [
    [],
    [{"role": "outil", "content": "x"}],
    [{"role": "user", "content": None}],
])
async def test_conversation_invalide_refusee_sans_appel(nom, messages):
    journal = Journal()
    f = FABRIQUES[nom](Scenario(), journal)
    with pytest.raises(ValueError):
        await lire(f, messages=messages)
    assert journal.requetes == []


async def test_modele_obligatoire(nom):
    with pytest.raises(ValueError):
        FABRIQUES[nom](Scenario(), modele="")


async def test_repr_sans_cle(nom):
    f = FABRIQUES[nom](Scenario())
    assert "cle-de-test" not in repr(f) and nom in repr(f)
