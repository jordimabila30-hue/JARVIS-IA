"""ODO, phase 1 : moteur universel (orchestrateur, registre, permissions,
validation, sécurité, confirmations) avec des outils fictifs et un
fournisseur scénarisé. Aucun appel réel.
"""

import asyncio
from typing import Any

import fakeredis
import pytest

from app.config import get_settings
from app.llm import ErreurLLM, Fin, FournisseurLLM, LimiteDebit, RaisonArret, Texte, TourAssistant, Usage
from app.llm.base import AppelOutil
from app.odo.confirmations import Confirmations, cle
from app.odo.contrat import ContexteOutil, DemandeConfirmation, EtatOutil, Outil, ResultatOutil, Sensibilite
from app.odo.orchestrateur import ExecutionODO
from app.odo.outils_fictifs import INJECTION, ActionFictive, outils_fictifs
from app.odo.permissions import PolitiqueOutils
from app.odo.registre import RegistreOutils, registre_actif
from app.odo.securite import envelopper, neutraliser
from app.odo.validation import valider, verifier_schema

USER = "11111111-1111-1111-1111-111111111111"
AUTRE = "99999999-9999-9999-9999-999999999999"


# --- Doublures ---------------------------------------------------------------------

def outil(id_: str, nom: str, **arguments) -> AppelOutil:
    return AppelOutil(id_, nom, arguments)


def tour(*appels: AppelOutil, texte: str = "", entree=100, sortie=20) -> list:
    return [*([Texte(texte)] if texte else []),
            Fin(RaisonArret.OUTIL, Usage(entree, sortie), "m", tour=TourAssistant(texte, tuple(appels), "faux"))]


def finale(texte="Voilà.", entree=150, sortie=30) -> list:
    return [Texte(texte), Fin(RaisonArret.FIN, Usage(entree, sortie), "m")]


class FauxLLM(FournisseurLLM):
    """Rejoue des tours scénarisés ; note ce que le modèle a reçu."""

    nom = "faux"

    def __init__(self, tours: list, *, erreur_au_tour: dict[int, Exception] | None = None) -> None:
        super().__init__("m")
        self.tours = list(tours)
        self.recus: list[tuple[list, list]] = []
        self.forces: list[bool] = []
        self.erreur_au_tour = erreur_au_tour or {}

    async def flux(self, messages, *, max_sortie, effort=None, outils=None, forcer_reponse=False):
        n = len(self.recus)
        self.recus.append((list(messages), list(outils or [])))
        self.forces.append(forcer_reponse)
        if n in self.erreur_au_tour:
            raise self.erreur_au_tour[n]
        for ev in self.tours.pop(0):
            yield ev

    async def json(self, *a, **k):
        raise NotImplementedError


class Lent(Outil):
    nom = "lent"
    description = "Ne répond jamais à temps."
    schema = {"type": "object", "properties": {}, "additionalProperties": False}

    async def executer(self, arguments, contexte):
        await asyncio.sleep(10)
        return ResultatOutil("trop tard")


class Casse(Outil):
    nom = "casse"
    description = "Lève une exception contenant une donnée."
    schema = {"type": "object", "properties": {}, "additionalProperties": False}

    async def executer(self, arguments, contexte):
        raise RuntimeError("secret de l'utilisateur dans l'exception")


class Compteur(Outil):
    nom = "compteur"
    description = "Compte ses exécutions."
    schema = {"type": "object", "properties": {"n": {"type": "integer"}}, "additionalProperties": False}
    offres = frozenset({"pro"})

    def __init__(self):
        self.executions: list[str] = []

    async def executer(self, arguments, contexte):
        self.executions.append(contexte.user_id)
        return ResultatOutil(f"exécuté pour {contexte.user_id[:4]}")


QUESTION = [{"role": "system", "content": "Tu es JARVIS."}, {"role": "user", "content": "Question"}]


def contexte(**k) -> ContexteOutil:
    return ContexteOutil(**{"user_id": USER, "demande_id": "demande-1", "plan": "free",
                            "environnement": "development", **k})


@pytest.fixture
def redis():
    return fakeredis.FakeAsyncRedis(decode_responses=True)


@pytest.fixture(autouse=True)
def vider_actions():
    ActionFictive.executions.clear()


def execution(llm, *outils, redis=None, ctx=None, budget=None, **reglages) -> ExecutionODO:
    registre = RegistreOutils(list(outils) or outils_fictifs())
    return ExecutionODO(
        llm=llm, registre=registre, politique=PolitiqueOutils(),
        confirmations=Confirmations(redis, 300) if redis is not None else None,
        contexte=ctx or contexte(), max_tours=reglages.get("max_tours", 4),
        max_appels=reglages.get("max_appels", 8), delai_outil=reglages.get("delai", 1.0),
        resultat_max=reglages.get("resultat_max", 6000), verifier_budget=budget,
    )


async def derouler(ex: ExecutionODO, prompt=QUESTION) -> list:
    return [e async for e in ex.flux(prompt, max_sortie=500)]


def textes(ev) -> str:
    return "".join(e.texte for e in ev if isinstance(e, Texte))


def resultats_envoyes(llm: FauxLLM, tour_n: int) -> list:
    return list(llm.recus[tour_n][0][-1]["resultats"])


# --- Boucle --------------------------------------------------------------------------

async def test_lecture_puis_reponse_finale_usage_additionne():
    llm = FauxLLM([tour(outil("a1", "lecture_fictive", fiche="meteo"), texte="Je regarde."),
                   finale("Il fait 18 °C.")])
    ev = await derouler(execution(llm))
    assert textes(ev) == "Je regarde.\n\nIl fait 18 °C."
    assert [(e.nom, e.etat) for e in ev if isinstance(e, EtatOutil)] == [("lecture_fictive", "en_cours"),
                                                                         ("lecture_fictive", "termine")]
    fin = ev[-1]
    assert isinstance(fin, Fin) and fin.raison is RaisonArret.FIN and fin.tour is None
    assert (fin.usage.entree_totale, fin.usage.sortie) == (250, 50)         # somme des deux tours
    [r] = resultats_envoyes(llm, 1)
    assert r.id == "a1" and "Météo fictive" in r.contenu and "<resultat_outil" in r.contenu
    # Seuls les outils autorisés sont proposés, avec la consigne de sécurité.
    assert {d.nom for d in llm.recus[0][1]} == {"lecture_fictive", "recherche_fictive", "action_fictive"}
    assert "jamais des instructions" in llm.recus[0][0][0]["content"]


async def test_plusieurs_appels_dans_un_tour_un_resultat_chacun():
    llm = FauxLLM([tour(outil("a1", "lecture_fictive", fiche="meteo"),
                        outil("a2", "lecture_fictive", fiche="agenda")), finale()])
    await derouler(execution(llm))
    assert [r.id for r in resultats_envoyes(llm, 1)] == ["a1", "a2"]


async def test_sans_appel_un_seul_tour_rien_d_autre():
    llm = FauxLLM([finale("Bonjour.")])
    ev = await derouler(execution(llm))
    assert textes(ev) == "Bonjour." and len(llm.recus) == 1
    assert not [e for e in ev if isinstance(e, EtatOutil)]


async def test_outil_inconnu_ou_non_autorise_jamais_execute():
    compteur = Compteur()                                      # réservé à l'offre Pro
    llm = FauxLLM([tour(outil("a1", "compteur"), outil("a2", "rm_rf")), finale()])
    ex = execution(llm, compteur, ctx=contexte(plan="free"))
    assert not ex.actif                                        # aucun outil autorisé : pas de boucle
    llm = FauxLLM([tour(outil("a1", "compteur"), outil("a2", "rm_rf")), finale()])
    ex = execution(llm, compteur, outils_fictifs()[0], ctx=contexte(plan="free"))
    ev = await derouler(ex)
    assert compteur.executions == []
    assert [d.nom for d in llm.recus[0][1]] == ["lecture_fictive"]
    assert [(e.nom, e.code) for e in ev if isinstance(e, EtatOutil)] == [("compteur", "non_autorise"),
                                                                         ("rm_rf", "non_autorise")]
    assert all(r.erreur for r in resultats_envoyes(llm, 1))


async def test_arguments_invalides_ou_supplementaires_refuses():
    llm = FauxLLM([tour(outil("a1", "lecture_fictive", fiche="banque"),
                        outil("a2", "lecture_fictive", fiche="meteo", user_id=AUTRE),
                        AppelOutil("a3", "lecture_fictive", erreur_arguments="JSON illisible")), finale()])
    ev = await derouler(execution(llm))
    assert [e.code for e in ev if isinstance(e, EtatOutil)] == ["arguments_invalides", "arguments_invalides",
                                                                "arguments_illisibles"]
    r = resultats_envoyes(llm, 1)
    assert all(x.erreur for x in r) and "valeur non autorisée" in r[0].contenu and "champ inconnu" in r[1].contenu


async def test_delai_depasse_et_panne_d_outil():
    llm = FauxLLM([tour(outil("a1", "lent"), outil("a2", "casse")), finale()])
    ev = await derouler(execution(llm, Lent(), Casse(), delai=0.05))
    assert [e.code for e in ev if isinstance(e, EtatOutil) and e.etat == "erreur"] == ["delai_depasse", "echec_outil"]
    r = resultats_envoyes(llm, 1)
    assert "secret" not in r[1].contenu                       # jamais le texte de l'exception


async def test_appel_identique_jamais_execute_deux_fois():
    compteur = Compteur()
    llm = FauxLLM([tour(outil("a1", "compteur", n=1)), tour(outil("a2", "compteur", n=1),
                                                             outil("a3", "compteur", n=2)), finale()])
    await derouler(execution(llm, compteur, ctx=contexte(plan="pro")))
    assert compteur.executions == [USER, USER]                # n=1 une seule fois, n=2 une fois
    assert resultats_envoyes(llm, 2)[0].contenu == resultats_envoyes(llm, 1)[0].contenu


async def test_boucle_infinie_bornee_par_les_tours():
    llm = FauxLLM([tour(outil(f"a{i}", "lecture_fictive", fiche="meteo")) for i in range(10)])
    with pytest.raises(ErreurLLM) as e:
        await derouler(execution(llm, max_tours=3))
    assert e.value.code == "odo_limite" and e.value.apres_texte
    assert len(llm.recus) == 3


async def test_trop_d_appels_refuses_au_dela_de_la_limite():
    llm = FauxLLM([tour(*[outil(f"a{i}", "recherche_fictive", requete=f"q{i}") for i in range(5)]), finale()])
    ev = await derouler(execution(llm, max_appels=2))
    assert [e.code for e in ev if isinstance(e, EtatOutil) and e.etat == "refuse"] == ["limite_appels"] * 3


async def test_budget_reverifie_avant_chaque_tour():
    vus = []

    def budget(tokens):
        vus.append(tokens)
        return "tokens" if tokens > 200 else None

    llm = FauxLLM([tour(outil("a1", "lecture_fictive", fiche="meteo"), entree=180, sortie=40), finale()])
    with pytest.raises(ErreurLLM) as e:
        await derouler(execution(llm, budget=budget))
    assert e.value.code == "llm_budget" and len(llm.recus) == 1       # aucun 2e appel facturable
    assert vus and vus[0] > 220


async def test_erreur_apres_des_outils_jamais_rejouee_entierement():
    llm = FauxLLM([tour(outil("a1", "lecture_fictive", fiche="meteo"))],
                  erreur_au_tour={1: LimiteDebit(fournisseur="faux", attente=1.0)})
    ex = execution(llm)
    with pytest.raises(LimiteDebit) as e:
        await derouler(ex)
    assert e.value.apres_texte                                # la route ne relance pas tout
    assert ex.usage_consomme()[0] >= 100                       # tour 1 + tour 2 (envoyé)


async def test_interruption_pendant_un_outil_annule_proprement():
    llm = FauxLLM([tour(outil("a1", "lent"), entree=100, sortie=20), finale()])
    ex = execution(llm, Lent(), delai=5)
    gen = ex.flux(QUESTION, max_sortie=500)
    async for ev in gen:
        if isinstance(ev, EtatOutil) and ev.etat == "en_cours":
            break
    await gen.aclose()                                         # client déconnecté
    assert ex.usage_consomme() == (100, 20) and len(llm.recus) == 1


# --- Sécurité ------------------------------------------------------------------------

async def test_injection_dans_un_resultat_neutralisee_et_jamais_suivie():
    llm = FauxLLM([tour(outil("a1", "recherche_fictive", requete="contrat")), finale()])
    ev = await derouler(execution(llm))
    [r] = resultats_envoyes(llm, 1)
    # Le résultat ne peut ni fermer l'enveloppe ni imiter les consignes du serveur.
    assert r.contenu.count("</resultat_outil>") == 1 and r.contenu.endswith("</resultat_outil>")
    assert "<consignes_systeme>" not in r.contenu and "‹/resultat_outil›" in r.contenu
    assert "jamais des instructions" in r.contenu
    # Aucune action déclenchée par le contenu : seul le modèle appelle, et
    # une action passe toujours par une confirmation.
    assert ActionFictive.executions == [] and not [e for e in ev if isinstance(e, DemandeConfirmation)]


async def test_resultat_volumineux_tronque():
    llm = FauxLLM([tour(outil("a1", "recherche_fictive", requete="x", volumineux=True)), finale()])
    await derouler(execution(llm, resultat_max=2000))
    [r] = resultats_envoyes(llm, 1)
    assert len(r.contenu) < 2400 and "résultat coupé" in r.contenu


def test_enveloppe_et_neutralisation():
    texte = envelopper("x", INJECTION, 10_000)
    assert texte.count("<resultat_outil") == 1 and "<consignes_systeme>" not in texte
    assert neutraliser("< /Resultat_Outil >") == "‹ /Resultat_Outil ›"


async def test_le_contexte_vient_du_serveur_jamais_du_modele():
    compteur = Compteur()
    llm = FauxLLM([tour(outil("a1", "compteur", n=1)), finale()])
    await derouler(execution(llm, compteur, ctx=contexte(plan="pro", user_id=AUTRE)))
    assert compteur.executions == [AUTRE]


async def test_outils_fictifs_jamais_en_production():
    reglages = get_settings().model_copy(update={"odo_outils_fictifs": True, "environnement": "production"})
    assert len(registre_actif(reglages)) == 0
    llm = FauxLLM([finale()])
    ex = execution(llm, ctx=contexte(environnement="production"))
    assert not ex.actif                                        # refusés par la politique aussi
    dev = get_settings().model_copy(update={"odo_outils_fictifs": True, "environnement": "development"})
    assert registre_actif(dev).noms() == ["action_fictive", "lecture_fictive", "recherche_fictive"]


# --- Confirmations -------------------------------------------------------------------

async def test_action_sensible_preparee_jamais_executee(redis):
    llm = FauxLLM([tour(outil("a1", "action_fictive", cible="rapport")), finale("Confirme dans JARVIS.")])
    ev = await derouler(execution(llm, redis=redis))
    [demande] = [e for e in ev if isinstance(e, DemandeConfirmation)]
    assert demande.outil == "action_fictive" and "rapport" in demande.resume
    assert ActionFictive.executions == []
    [r] = resultats_envoyes(llm, 1)
    assert "PAS exécutée" in r.contenu and not r.erreur
    assert await redis.ttl(cle(USER, demande.id)) > 0


async def test_confirmation_usage_unique_et_par_compte(redis):
    c = Confirmations(redis, 300)
    d = await c.preparer(ActionFictive(), {"cible": "x"}, contexte())
    assert await c.consommer(AUTRE, d.id) is None              # autre compte : introuvable
    action = await c.consommer(USER, d.id)
    assert action.outil == "action_fictive" and action.arguments == {"cible": "x"}
    assert await c.consommer(USER, d.id) is None               # déjà utilisée


async def test_confirmation_expiree(redis):
    c = Confirmations(redis, 1)
    d = await c.preparer(ActionFictive(), {"cible": "x"}, contexte())
    await redis.delete(cle(USER, d.id))                        # expiration (TTL écoulé)
    assert await c.consommer(USER, d.id) is None


async def test_sans_redis_aucune_action_preparee():
    class RedisEnPanne:
        async def set(self, *a, **k):
            raise ConnectionError("redis absent")

    llm = FauxLLM([tour(outil("a1", "action_fictive", cible="x")), finale()])
    ex = execution(llm)
    ex.confirmations = Confirmations(RedisEnPanne(), 300)
    ev = await derouler(ex)
    assert [e.code for e in ev if isinstance(e, EtatOutil)] == ["confirmation_indisponible"]
    assert resultats_envoyes(llm, 1)[0].erreur and ActionFictive.executions == []


# --- Registre et validation ----------------------------------------------------------

def test_ajouter_une_competence_sans_toucher_l_orchestrateur():
    class Nouvelle(Outil):
        nom = "nouvelle_competence"
        description = "Exemple."
        schema = {"type": "object", "properties": {"x": {"type": "string"}}, "required": ["x"]}

        async def executer(self, arguments: dict[str, Any], contexte):
            return ResultatOutil("ok")

    r = RegistreOutils(outils_fictifs())
    r.enregistrer(Nouvelle())
    assert "nouvelle_competence" in r.noms()
    with pytest.raises(ValueError):
        r.enregistrer(Nouvelle())                              # doublon
    mauvais = Nouvelle()
    mauvais.nom = "Mauvais Nom"
    with pytest.raises(ValueError):
        RegistreOutils([mauvais])


def test_validation_stricte():
    s = {"type": "object", "properties": {
        "n": {"type": "integer", "minimum": 1, "maximum": 5},
        "mots": {"type": "array", "items": {"type": "string", "maxLength": 3}, "maxItems": 2},
        "ok": {"type": "boolean"}}, "required": ["n"], "additionalProperties": False}
    verifier_schema(s)
    assert valider(s, {"n": 3, "mots": ["a"], "ok": True}) == []
    assert valider(s, {"n": True}) == ["arguments.n : integer attendu"]        # booléen ≠ nombre
    erreurs = valider(s, {"n": 9, "mots": ["abcd", "b", "c"], "x": 1})
    assert len(erreurs) == 4
    assert valider(s, {}) == ["arguments.n : obligatoire"]
    with pytest.raises(ValueError):
        verifier_schema({"type": "object", "$ref": "#/x"})                   # mot-clé non pris en charge


async def test_contexte_outil_identique_pour_tous_les_fournisseurs():
    # ODO ne connaît que le contrat commun : le même scénario vaut pour
    # n'importe quel fournisseur sélectionné par MIA (voir test_odo_chat).
    llm = FauxLLM([tour(outil("a1", "lecture_fictive", fiche="agenda")), finale()])
    ev = await derouler(execution(llm))
    assert isinstance(ev[-1], Fin) and ev[-1].modele == "m"


async def test_dernier_tour_reponse_forcee_jamais_d_erreur_seche():
    # Le modèle lit les e-mails un par un : au dernier tour permis, il doit
    # répondre avec ce qu'il a déjà lu (outils interdits pour ce tour).
    llm = FauxLLM([tour(outil("a1", "lecture_fictive", fiche="meteo")),
                   tour(outil("a2", "lecture_fictive", fiche="agenda")),
                   finale("Voici le point.")])
    ev = await derouler(execution(llm, max_tours=3))
    assert textes(ev) == "Voici le point." and isinstance(ev[-1], Fin)
    assert llm.forces == [False, False, True]


async def test_plus_d_appels_possibles_reponse_forcee():
    llm = FauxLLM([tour(outil("a1", "recherche_fictive", requete="a"), outil("a2", "recherche_fictive", requete="b")),
                   finale("Résumé.")])
    await derouler(execution(llm, max_appels=2))
    assert llm.forces == [False, True]
