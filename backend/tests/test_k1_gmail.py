"""K1 : corrections Gmail issues des essais réels sur Flutter Web (G1-G9).

Boîte et e-mails fictifs uniquement."""

import pytest

from app.api.v1 import chat
from app.integrations.gmail import ClientGmail, extraire
from app.odo.gmail_direct import reconnaitre
from app.odo.gmail_lecture import dossier
from app.odo.outils_gmail import CONSIGNE_DIRECTE, CONSIGNE_GMAIL, GmailRechercher, phrase_non_lus
from faux_google import b64, message
from faux_llm import SERVEURS, Scenario
from test_chat import USER
from test_gmail import connecter, env, evenements, jeton  # noqa: F401 (fixture)
from test_gmail_recherche import ctx


# --- G1 : nombre exact de non-lus, sans IA -------------------------------------

@pytest.mark.parametrize("question", [
    "Combien de mails non lus ai-je ?", "JARVIS, combien de messages non lus j'ai ?",
    "combien d'e-mails non lus dans ma boîte de réception ?", "Combien de non lus ?",
])
def test_compter_reconnu(question):
    assert reconnaitre(question) == {"compter_non_lus": True}


@pytest.mark.parametrize("question", ["Combien de mails non lus de Lumen ?", "Résume mes mails non lus"])
def test_compter_pas_pour_une_autre_demande(question):
    assert reconnaitre(question) != {"compter_non_lus": True}


def test_phrases_non_lus():
    assert phrase_non_lus(0, 0) == "Tu n'as aucun e-mail non lu dans ta boîte de réception."
    assert phrase_non_lus(1, 1) == "Tu as 1 e-mail non lu dans ta boîte de réception."
    assert "37 e-mails non lus" in phrase_non_lus(30, 37) and "30 conversations" in phrase_non_lus(30, 37)


async def test_compteur_exact_sans_appel_ia(env, caplog):
    await connecter(env)
    env.faux.messages = {f"n{i}aaaa": message(f"n{i}aaaa", non_lu=i < 9) for i in range(12)}
    serveur = SERVEURS["groq"](Scenario(textes=["ne doit pas servir"]))
    env.llm = serveur.fournisseur()
    with caplog.at_level("INFO", logger="app.odo"):
        r = await env.client.post("/api/v1/chat/stream", json={"message": "Combien de mails non lus ai-je ?"},
                                  headers=jeton(USER))
        await chat.wait_background_tasks()
    ev = evenements(r.text)
    assert ev[-1][0] == "done"
    texte = "".join(d["text"] for e, d in ev if e == "delta")
    assert texte == "Tu as 9 e-mails non lus dans ta boîte de réception."
    assert serveur.requetes == []                                   # aucun appel au modèle
    assert [q.url.path.rsplit("/", 1)[-1] for q in env.faux.gmail if not q.url.path.endswith("profile")] == ["INBOX"]
    assert any("direct=1" in x.getMessage() and "tours=0" in x.getMessage() for x in caplog.records)


# --- G2 : HTML et corps multipart -------------------------------------------------

AMBASSADE = """<html><head><style>p{color:red}</style><title>Termin</title></head><body>
<!-- Vorlage 3 --><table><tr><td>Sehr geehrte Frau Potts,</td></tr>
<tr><td><p>Ihr Termin bei der Visastelle ist am <b>12.&nbsp;November&nbsp;2026 um 09:30 Uhr</b>.</p>
<p>Bitte bringen Sie Ihren Reisepass mit.</p></td></tr></table></body></html>"""


def _multipart(plain: str | None, html: str | None = None, *, charge: str | None = None, charset="utf-8"):
    parts = []
    if plain is not None:
        parts.append({"mimeType": "text/plain", "body": {"data": b64(plain)}})
    if html is not None:
        parts.append({"mimeType": "text/html", "headers": [
            {"name": "Content-Type", "value": f'text/html; charset="{charset}"'}],
            "body": {"data": b64(html)} if charge is None else {"attachmentId": charge, "size": 90_000}})
    return {"mimeType": "multipart/alternative", "parts": parts}


def test_html_seul_lisible():
    texte, _ = extraire(_multipart(None, AMBASSADE))
    assert "12. November 2026 um 09:30 Uhr" in texte and "Reisepass" in texte
    assert "color" not in texte and "Vorlage" not in texte and "Termin\n" not in texte[:6]


def test_texte_brut_reduit_a_un_reste_html_prefere():
    texte, _ = extraire(_multipart("Ihr E-Mail-Programm unterstützt kein HTML.", AMBASSADE))
    assert "09:30" in texte


def test_texte_brut_complet_garde():
    texte, _ = extraire(_multipart("Rendez-vous le 12 novembre à 9 h 30.", "<p>Rendez-vous le 12 novembre</p>"))
    assert texte == "Rendez-vous le 12 novembre à 9 h 30."


def test_charset_latin1():
    import base64
    donnees = base64.urlsafe_b64encode("<p>Rendez-vous confirmé à Genève</p>".encode("latin-1")).decode()
    payload = {"mimeType": "text/html", "headers": [{"name": "Content-Type", "value": "text/html; charset=ISO-8859-1"}],
               "body": {"data": donnees}}
    assert extraire(payload)[0] == "Rendez-vous confirmé à Genève"


async def test_gros_corps_html_telecharge(env):
    await connecter(env)
    m = message("amb1aaaa", de="Botschaft <visa@botschaft.test>", objet="Ihr Termin")
    m["payload"]["parts"] = _multipart(None, AMBASSADE, charge="corpsHTML1")["parts"]
    env.faux.messages = {"amb1aaaa": m}
    env.faux.corps_charges = {"corpsHTML1": b64(AMBASSADE)}
    e = await ClientGmail(env.google).message(USER, "amb1aaaa", 4000)
    assert "09:30 Uhr" in e.texte and e.pieces_jointes == []
    assert all(q.method == "GET" for q in env.faux.gmail)


def test_date_de_reception_jamais_date_du_rendez_vous():
    m = message("amb2aaaa", de="Botschaft <visa@botschaft.test>", objet="Ihr Termin",
                date="Mon, 19 Oct 2026 08:00:00 +0200")
    from app.integrations.gmail import _email
    m["payload"]["parts"] = _multipart(None, AMBASSADE)["parts"]
    bloc = dossier([_email(m, 4000)], 4000, 120)
    assert "Reçu le : " in bloc and "Date : " not in bloc
    assert "jamais celle d'un rendez-vous" in CONSIGNE_DIRECTE


# --- G4, G5, G7, G8, G9 ---------------------------------------------------------

def test_meme_expediteur_le_plus_recent_fait_foi():
    from app.integrations.gmail import _email
    a = _email(message("sl1aaaa", de="Starlink <noreply@starlink.test>", objet="Alerte", fil="fA",
                       date="Mon, 12 Oct 2026 08:00:00 +0200", texte="Vous avez utilisé 80 % de vos données."), 2000)
    b = _email(message("sl2aaaa", de="Starlink <noreply@starlink.test>", objet="Service suspendu", fil="fB",
                       date="Mon, 19 Oct 2026 08:00:00 +0200", texte="450 Go utilisés : service suspendu."), 2000)
    bloc = dossier([b, a], 2000, 120)
    assert "suite du message 1 du même expéditeur" in bloc
    assert "pourcentage ≠ volume" in CONSIGNE_GMAIL


def test_regles_authenticite_pieces_jointes_longueur():
    for regle in ("jamais qu'un e-mail est authentique", "jamais affirmé", "respectée strictement", "exclure"):
        assert regle in CONSIGNE_GMAIL
    assert "jamais qu'un e-mail est authentique" in CONSIGNE_DIRECTE


async def test_exclure_ecarte_les_emails_deja_vus(env):
    await connecter(env)
    env.faux.filtrer = True
    env.faux.messages = {
        "st1aaaa": message("st1aaaa", de="Starlink <noreply@starlink.test>", objet="Facture", texte="Votre facture."),
        "ax1aaaa": message("ax1aaaa", de="Axa <contact@axa.test>", objet="Facture", texte="Votre facture Axa."),
    }
    r = await GmailRechercher(ClientGmail(env.google)).executer({"termes": ["facture"], "exclure": ["st1aaaa"]},
                                                                ctx())
    assert [c["id"] for c in r.donnees["candidats"]] == ["ax1aaaa"]


async def test_plusieurs_sujets_une_question(env):
    await connecter(env)
    env.faux.filtrer = True
    env.faux.messages = {
        "as1aaaa": message("as1aaaa", de="Assurance Lumen <a@assur.test>", objet="Votre rendez-vous",
                           texte="Votre rendez-vous avec un conseiller."),
        "em1aaaa": message("em1aaaa", de="Botschaft <visa@botschaft.test>", objet="Votre rendez-vous",
                           texte="Votre rendez-vous à l'ambassade."),
    }
    r = await GmailRechercher(ClientGmail(env.google)).executer({"termes": ["rendez-vous"], "max": 1, "lire": True},
                                                                ctx())
    assert "pose UNE question courte" in r.contenu


async def test_liste_tronquee_jamais_donnee_comme_total(env):
    """GH-60 : Gmail annonce une page suivante → « au moins N », jamais N."""
    await connecter(env)
    env.faux.filtrer = True
    env.faux.messages = {
        f"fa{i}aaaa": message(f"fa{i}aaaa", de="Banque <b@banque.test>", objet=f"Relevé {i}", texte="Relevé.")
        for i in range(5)
    }
    r = await GmailRechercher(ClientGmail(env.google)).executer({"lire": True, "max": 2}, ctx())
    assert r.donnees["complet"] is False
    assert "au moins 2" in r.contenu

    env.faux.messages = {"fa0aaaa": env.faux.messages["fa0aaaa"]}
    r = await GmailRechercher(ClientGmail(env.google)).executer({"lire": True, "max": 2}, ctx())
    assert r.donnees["complet"] is True
    assert "LIMITÉE" not in r.contenu


# --- G3 / K1-15 : conversation classée sous Gmail -------------------------------

async def test_reponse_gmail_marquee_source_gmail(env):
    await connecter(env)
    env.faux.messages = {"m1aaaa": message("m1aaaa", de="Recrutement Lumen <rh@lumen.test>")}
    env.llm = SERVEURS["groq"](Scenario(textes=["Lumen a reçu ta candidature."])).fournisseur()
    await env.client.post("/api/v1/chat/stream", json={"message": "Résume le mail de Lumen"}, headers=jeton(USER))
    await chat.wait_background_tasks()
    [ligne] = [r for r in env.supa.inserted if r["role"] == "assistant"]
    assert {"type": "source", "source": "gmail"} in ligne["attachments"]


async def test_chat_ordinaire_jamais_marque(env):
    await connecter(env)
    env.llm = SERVEURS["groq"](Scenario(textes=["Bonjour !"])).fournisseur()
    await env.client.post("/api/v1/chat/stream", json={"message": "Raconte une blague"}, headers=jeton(USER))
    await chat.wait_background_tasks()
    [ligne] = [r for r in env.supa.inserted if r["role"] == "assistant"]
    assert {"type": "source", "source": "gmail"} not in (ligne.get("attachments") or [])
