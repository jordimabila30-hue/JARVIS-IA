"""Gmail, phase 2 : ce que le modèle REÇOIT pour comprendre (sans IA).

Pour chacun des 18 scénarios fictifs (`scenarios_gmail.py`), l'outil réel lit
les e-mails du faux Google et le dossier transmis au modèle est contrôlé :
texte cité étiqueté, dates locales, ordre chronologique, repères, pièces
jointes non lues, secrets masqués, injection neutralisée, isolation. La
compréhension par les vrais modèles est mesurée par `evaluation_gmail.py`.
"""

import pytest

from app.api.v1 import chat
from app.integrations.gmail import ClientGmail
from app.odo.contrat import ContexteOutil
from app.odo.gmail_lecture import chronologie, date_locale, decouper, reperes
from app.odo.outils_gmail import CONSIGNE_GMAIL, GmailLireFil, GmailLireMessage, GmailPreparerResume
from app.odo.securite import envelopper
from app.odo.service import ServiceODO
from faux_google import message
from faux_llm import SERVEURS, Scenario
from scenarios_gmail import SCENARIOS, ScenarioGmail
from test_chat import OWN_CONV, USER
from test_gmail import AUTRE, connecter, env, evenements, jeton  # noqa: F401 (fixture)

settings = chat.get_settings()
OUTILS = {"gmail_lire_message": GmailLireMessage, "gmail_lire_fil": GmailLireFil,
          "gmail_preparer_resume": GmailPreparerResume}


def ctx(user=USER, conversation=None) -> ContexteOutil:
    return ContexteOutil(user_id=user, demande_id="d1", plan="free", connexions=frozenset({"gmail"}),
                         decalage_minutes=60, conversation_id=conversation)


def charger(env, s: ScenarioGmail) -> None:
    env.faux.messages = {i: message(i, de=m["de"], objet=m["objet"], date=m["date"], texte=m["texte"],
                                    fil=m["fil"], pieces=m["pieces"], important=m["important"])
                         for i, m in s.emails.items()}


async def lire(env, s: ScenarioGmail, user=USER):
    r = await OUTILS[s.outil](ClientGmail(env.google)).executer(s.arguments, ctx(user))
    return r, envelopper(s.outil, r.contenu, settings.odo_resultat_max_caracteres)


@pytest.mark.parametrize("s", [s for s in SCENARIOS if s.dossier_doit or s.dossier_interdit], ids=lambda s: s.nom)
async def test_dossier_transmis_au_modele(env, s):
    await connecter(env)
    charger(env, s)
    r, envoye = await lire(env, s)
    assert r.erreur is None, r.contenu
    for attendu in s.dossier_doit:
        assert attendu in envoye, (attendu, envoye)
    for interdit in s.dossier_interdit:
        assert interdit not in envoye, (interdit, envoye)


async def test_18_isolation_la_boite_d_un_autre_compte_est_inaccessible(env):
    await connecter(env, USER)
    s = next(x for x in SCENARIOS if x.nom == "18_isolation")
    charger(env, s)
    r, _ = await lire(env, s, AUTRE)
    assert r.erreur == "gmail_non_connecte" and "Message privé" not in r.contenu


# --- Lecture : texte cité, transfert, dates, ordre, repères ---------------------------------------

@pytest.mark.parametrize("entete", [
    "Le lun. 12 oct. 2026 à 08:00, Mme Ndiaye <n@x.test> a écrit :",
    "On Mon, Oct 12, 2026 at 8:00 AM Jane <j@x.test> wrote:",
    "Am Mo., 12. Okt. 2026 um 08:00 Uhr schrieb Jan <j@x.test>:",
    "-----Original Message-----",
])
def test_texte_cite_separe_du_nouveau(entete):
    nouveau, cite, transfere = decouper(f"C'est noté pour vendredi.\n\n{entete}\nLa réunion aura lieu mardi.")
    assert nouveau == "C'est noté pour vendredi." and "mardi" in cite and transfere == ""


def test_citation_outlook_et_chevrons():
    n, c, _ = decouper("Merci !\nDe : Jean <j@x.test>\nEnvoyé : lundi 12 octobre 2026\nObjet : X\nAncien texte")
    assert (n, "Ancien texte" in c) == ("Merci !", True)
    n, c, _ = decouper("Oui.\n> ligne 1\n> ligne 2")
    assert (n, c) == ("Oui.", "ligne 1\nligne 2")
    n, c, _ = decouper("Une seule > flèche dans une phrase.")
    assert c == ""


def test_message_transfere_garde_et_etiquete():
    n, c, t = decouper("Pour info.\n---------- Forwarded message ---------\nDe : RH\nVotre contrat commence lundi.")
    assert n == "Pour info." and "contrat commence lundi" in t


def test_dates_dans_l_heure_de_l_utilisateur():
    assert date_locale("Mon, 19 Oct 2026 02:03:00 -0700", 60) == "lundi 19 octobre 2026 à 10:03 (heure de l'utilisateur)"
    assert date_locale("Mon, 19 Oct 2026 02:03:00 -0700", None).endswith("09:03 (UTC)")
    assert date_locale("pas une date", 60) == "pas une date"


def test_chronologie_sans_doublon():
    from app.integrations.gmail import Email
    def e(i, d):
        return Email(id=i, fil="f", de="x", objet="o", date=d, extrait="")
    ordre = chronologie([e("b", "Wed, 14 Oct 2026 09:00:00 +0200"), e("a", "Mon, 12 Oct 2026 09:00:00 +0200"),
                         e("b", "Wed, 14 Oct 2026 09:00:00 +0200")])
    assert [x.id for x in ordre] == ["a", "b"]


@pytest.mark.parametrize("texte,attendu", [
    ("Nous ne pourrons malheureusement pas donner suite.", "issue négative"),
    ("We regret to inform you that your application has not been successful.", "issue négative"),
    ("Leider können wir Ihnen keine Zusage geben.", "issue négative"),
    ("Merci de transmettre le document avant le 25 octobre.", "échéance"),
    ("Bitte senden Sie uns bis zum 30. Oktober Ihr Zeugnis.", "demande"),
    ("You may send it if you wish.", "simple possibilité"),
    ("Accepté sous réserve de la validation finale.", "réserve / condition"),
    ("The meeting has been rescheduled to Friday.", "changement"),
    ("Nous avons bien reçu votre dossier.", "réception"),
])
def test_reperes_multilingues(texte, attendu):
    assert attendu in reperes(texte, avec_phrases=False)


def test_reperes_jamais_tires_du_texte_cite():
    s = next(x for x in SCENARIOS if x.nom == "15_ancienne_info_citee")
    nouveau, cite, _ = decouper(s.emails["m15aaaa"]["texte"])
    assert "demande" not in reperes(nouveau, avec_phrases=False)       # « Merci de prévenir » est cité
    assert "Merci de prévenir" in cite


def test_consigne_de_comprehension():
    for attendu in ("Reçu ≠ accepté", "« sous réserve »", "ne pas donner suite", "simple possibilité",
                    "MÊME chose", "n'est pas une nouvelle information", "jamais lue",
                    "pas seulement le libellé « important »", "relis l'e-mail par son id",
                    "langue de l'utilisateur", "va à l'essentiel"):
        assert attendu in CONSIGNE_GMAIL, attendu


# --- Questions de suivi : les e-mails LUS sont mémorisés pour le chat ------------------------------

@pytest.mark.parametrize("nom", ["groq", "anthropic"])
async def test_suivi_le_modele_sait_quels_mails_relire(env, nom):
    await connecter(env)
    s = next(x for x in SCENARIOS if x.nom == "02_recu_non_accepte")
    charger(env, s)
    serveur = SERVEURS[nom](Scenario(textes=["Le lycée a bien reçu ton dossier."]),
                            etapes=[Scenario(textes=[], appels=[("a1", "gmail_lire_message", {"id": "m02aaaa"})])])
    env.llm = serveur.fournisseur()
    corps = {"message": "Qu'a dit le lycée Senghor ?", "conversation_id": OWN_CONV, "fuseau_minutes": 60}
    await env.client.post("/api/v1/chat/stream", json=corps, headers=jeton(USER))
    await chat.wait_background_tasks()
    # Suivi : « Donc c'est accepté ? » → l'id du mail lu est redonné, pour relire plutôt que deviner.
    serveur2 = SERVEURS[nom](Scenario(textes=["Pas encore : aucune décision n'est annoncée."]),
                             etapes=[Scenario(textes=[], appels=[("a2", "gmail_lire_message", {"id": "m02aaaa"})])])
    env.llm = serveur2.fournisseur()
    r = await env.client.post("/api/v1/chat/stream", json={**corps, "message": "Donc c'est accepté ?"},
                              headers=jeton(USER))
    await chat.wait_background_tasks()
    assert evenements(r.text)[-1][0] == "done"
    premiere = str(serveur2.requetes[0]["messages"])
    assert "E-mails déjà LUS dans ce chat" in premiere and "id=m02aaaa" in premiere
    assert "Nous reviendrons vers vous" not in premiere          # jamais le texte dans la mémoire
    assert "après son examen" in str(serveur2.requetes[-1]["messages"])     # relu


async def test_memoire_des_mails_lus_isolee(env):
    await connecter(env)
    odo = ServiceODO(settings.model_copy(update=env.reglages), env.redis, google=env.google)
    execution = odo.execution(SERVEURS["groq"]().fournisseur(), ctx(conversation=OWN_CONV))
    execution.donnees.append(("gmail_lire_message", {"lus": [{"id": "m1aaaa", "fil": "f", "de": "a", "objet": "o",
                                                              "date": "d", "lu": "oui"}]}))
    await odo.memoriser(execution, OWN_CONV)
    assert "id=m1aaaa" in await odo.rappel(ctx(conversation=OWN_CONV))
    assert await odo.rappel(ctx(AUTRE, conversation=OWN_CONV)) is None
