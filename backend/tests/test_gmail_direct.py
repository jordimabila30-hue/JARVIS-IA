"""GMAIL 1 : chemin direct ODO (un seul appel IA) et repli sur le chemin habituel."""

import pytest

from app.api.v1 import chat
from app.odo.gmail_direct import reconnaitre
from faux_google import message
from faux_llm import SERVEURS, Scenario
from test_chat import USER
from test_gmail import AUTRE, connecter, env, evenements, jeton  # noqa: F401 (fixture)


@pytest.mark.parametrize("question,attendu", [
    ("Résume mes trois derniers mails.", {"lire": True, "max": 3}),
    ("JARVIS, résume mes 3 derniers mails", {"lire": True, "max": 3}),
    ("Lis mes mails non lus", {"lire": True, "non_lus": True}),
    ("Résume rapidement mes derniers mails", {"lire": True}),
    ("Résume mes mails de cette semaine", {"lire": True, "periode": "cette_semaine"}),
    ("Fais-moi un point sur mes mails d'aujourd'hui", {"lire": True, "periode": "aujourd_hui"}),
    ("Résume le mail de Lumen", {"lire": True, "expediteurs": ["lumen"], "max": 1}),
    ("Résume le dernier mail de la Commission des bourses", {"lire": True, "expediteurs": ["commission des bourses"],
                                                              "max": 1}),
])
def test_demandes_simples_chemin_direct(question, attendu):
    assert reconnaitre(question) == attendu


@pytest.mark.parametrize("question", [
    "Retrouve le mail dont je t'ai parlé hier.",
    "Le professeur m'a répondu concernant mon dossier ?",
    "Et l'autre message, qu'est-ce qu'il voulait dire ?",
    "Recherche la réponse à ma demande d'inscription, mais pas celle de l'année dernière.",
    "Est-ce que mon inscription est acceptée ?",
    "Fais-moi un point sur les messages importants de cette semaine.",
    "Et le deuxième message ?",
    "Mes mails",
    "Résume mes 50 derniers mails",
    "Quelle heure est-il ?",
    "Résume ce mail",
    "Résume le mail de mon école sur l'inscription",
])
def test_demandes_complexes_chemin_habituel(question):
    assert reconnaitre(question) is None


def boite(env):
    env.faux.filtrer = True
    env.faux.messages = {
        "m1aaaa": message("m1aaaa", de="Recrutement Lumen <rh@lumen.test>", objet="Votre candidature",
                          date="Mon, 19 Oct 2026 09:00:00 +0200",
                          texte="Nous avons bien reçu votre candidature. Une décision vous sera communiquée plus tard."
                                " Votre code de vérification est 482 913."),
        "m2aaaa": message("m2aaaa", de="Club Photo <club@photo.test>", objet="Sortie",
                          date="Sun, 18 Oct 2026 09:00:00 +0200", texte="Sortie photo dimanche si vous le souhaitez."),
    }


@pytest.mark.parametrize("nom", ["groq", "anthropic"])
async def test_un_seul_appel_ia_sans_outils(env, nom, caplog):
    await connecter(env)
    boite(env)
    serveur = SERVEURS[nom](Scenario(textes=["Lumen a reçu ta candidature ; la décision viendra plus tard."]))
    env.llm = serveur.fournisseur()
    with caplog.at_level("INFO", logger="app.odo"):
        r = await env.client.post("/api/v1/chat/stream", json={"message": "Résume le mail de Lumen",
                                                               "fuseau_minutes": 60}, headers=jeton(USER))
        await chat.wait_background_tasks()
    ev = evenements(r.text)
    assert ev[-1][0] == "done"
    assert len(serveur.requetes) == 1                                    # UN seul appel au fournisseur
    requete = serveur.requetes[0]
    assert "tools" not in requete                                        # aucune définition d'outil envoyée
    envoye = str(requete)
    assert "Nous avons bien reçu votre candidature" in envoye           # le texte, lu par ODO
    assert "482" not in envoye and "[code masqué]" in envoye             # secrets masqués comme avant
    assert "CHERCHER" not in envoye                                      # consigne de recherche non envoyée
    assert [d["nom"] for e, d in ev if e == "outil" and d["etat"] == "termine"] == ["gmail_rechercher"]
    [fin] = [x.getMessage() for x in caplog.records if x.getMessage().startswith("ODO fin")]
    assert "tours=1" in fin and "direct=1" in fin
    assert all(q.method == "GET" for q in env.faux.gmail)


async def test_rien_de_pertinent_repli_sur_le_chemin_habituel(env):
    await connecter(env)
    boite(env)
    serveur = SERVEURS["groq"](Scenario(textes=["Je n'ai rien trouvé de Zorglub."]),
                               etapes=[Scenario(textes=[], appels=[("a1", "gmail_rechercher",
                                                                    {"expediteurs": ["Zorglub SA"]})])])
    env.llm = serveur.fournisseur()
    r = await env.client.post("/api/v1/chat/stream", json={"message": "Résume le mail de Zorglub"},
                              headers=jeton(USER))
    await chat.wait_background_tasks()
    assert evenements(r.text)[-1][0] == "done"
    assert len(serveur.requetes) == 2 and "tools" in serveur.requetes[0]   # le modèle a repris la main


async def test_demande_complexe_garde_les_outils(env):
    await connecter(env)
    boite(env)
    serveur = SERVEURS["groq"](Scenario(textes=["Tu parles de quel professeur ?"]))
    env.llm = serveur.fournisseur()
    await env.client.post("/api/v1/chat/stream", json={"message": "Le professeur m'a répondu ?"}, headers=jeton(USER))
    await chat.wait_background_tasks()
    assert "tools" in serveur.requetes[0] and env.faux.recherches == []   # clarification possible, rien de forcé


async def test_compte_sans_gmail_jamais_de_chemin_direct(env):
    await connecter(env, USER)
    boite(env)
    serveur = SERVEURS["groq"](Scenario(textes=["Connecte Gmail."]))
    env.llm = serveur.fournisseur()
    await env.client.post("/api/v1/chat/stream", json={"message": "Résume mes 3 derniers mails"}, headers=jeton(AUTRE))
    await chat.wait_background_tasks()
    assert env.faux.recherches == [] and "tools" not in serveur.requetes[0]


async def test_n_derniers_mails_lecture_minimale(env):
    from app.integrations.gmail import ClientGmail
    from app.odo.outils_gmail import GmailRechercher
    from test_gmail_recherche import ctx
    await connecter(env)
    boite(env)
    r = await GmailRechercher(ClientGmail(env.google)).executer(reconnaitre("Résume mes 2 derniers mails"), ctx())
    assert r.donnees["requetes_gmail"] == 1 + 2 + 2                  # liste de 2, en-têtes, textes


@pytest.mark.parametrize("question,termes", [
    ("Résume le fil sur la réunion de projet", ["reunion projet", "reunion", "projet"]),
    ("Résume le mail sur les informations de rentrée", ["informations rentree", "informations", "rentree"]),
])
def test_sujet_explicite_chemin_direct(question, termes):
    assert reconnaitre(question) == {"lire": True, "termes": termes, "max": 1}


async def test_discussion_lue_entiere_dans_le_chemin_direct(env):
    from app.integrations.gmail import ClientGmail
    from app.odo.outils_gmail import GmailRechercher
    from scenarios_resumes import BOITE
    from test_gmail_recherche import ctx
    await connecter(env)
    env.faux.filtrer = True
    env.faux.messages = {i: message(i, de=BOITE[i]["de"], objet=BOITE[i]["objet"], date=BOITE[i]["date"],
                                    texte=BOITE[i]["texte"], fil=BOITE[i]["fil"]) for i in ("b03aaaa", "b04aaaa")}
    r = await GmailRechercher(ClientGmail(env.google)).executer(
        reconnaitre("Résume le fil sur la réunion de projet"), ctx())
    assert "Message 2/2 (le plus récent)" in r.contenu and "27 octobre" in r.contenu
    assert r.contenu.count("aura lieu mardi 20 octobre") == 1               # ancien message, une seule fois
