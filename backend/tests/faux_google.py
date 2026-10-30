"""Faux Google (OAuth 2.0 + API Gmail) et faux stockage des connexions,
pour les tests de l'intégration Gmail. Aucun appel réseau, aucun vrai jeton.
"""

from __future__ import annotations

import base64
import json
import re
from email.utils import parsedate_to_datetime
from urllib.parse import parse_qs

import httpx

from app.integrations.google import PORTEE_GMAIL, ServiceGoogle


def b64(texte: str) -> str:
    return base64.urlsafe_b64encode(texte.encode()).decode().rstrip("=")


def message(id_, *, de="Prof Martin <martin@ecole.fr>", objet="Inscription", date="Sat, 18 Oct 2026 09:00:00 +0200",
            texte="Votre inscription est confirmée pour le 3 novembre.", html=None, fil=None, non_lu=True,
            pieces=(), important=True) -> dict:
    parts = [{"mimeType": "text/plain", "body": {"data": b64(texte)}}] if html is None else \
        [{"mimeType": "text/html", "body": {"data": b64(html)}}]
    parts += [{"mimeType": "application/pdf", "filename": p, "body": {"attachmentId": "att1", "size": 900_000}}
              for p in pieces]
    return {
        "id": id_, "threadId": fil or f"fil{id_}", "snippet": texte[:80],
        "labelIds": ["INBOX", *(["UNREAD"] if non_lu else []), *(["IMPORTANT"] if important else [])],
        "payload": {"mimeType": "multipart/mixed", "headers": [
            {"name": "From", "value": de}, {"name": "To", "value": "pepper@gmail.com"},
            {"name": "Subject", "value": objet}, {"name": "Date", "value": date}], "parts": parts},
    }


class FauxGoogle:
    """Répond comme accounts.google.com / oauth2 / gmail.googleapis.com."""

    def __init__(self) -> None:
        self.requetes: list[httpx.Request] = []
        self.messages: dict[str, dict] = {}
        self.portee = PORTEE_GMAIL
        self.email = "pepper@gmail.com"
        self.rafraichissement = "rt-google-1"
        self.revoques: list[str] = []
        self.refus_rafraichissement: str | None = None      # ex. "invalid_grant"
        self.acces_expire_une_fois = False
        self.statut_gmail: int | None = None                # force une erreur de l'API Gmail
        self.recherches: list[str] = []
        # True : la requête `q` est réellement évaluée (sous-ensemble de la
        # syntaxe Gmail : from:, to:, subject:, "mot", {… OU …}, after:/before:
        # en secondes, has:attachment, is:unread, is:important, in:sent).
        self.filtrer = False
        self.panne_recherche: Exception | None = None       # ex. httpx.ReadTimeout
        self.corps_charges: dict[str, str] = {}              # attachmentId → corps (gros HTML)

    @property
    def gmail(self) -> list[httpx.Request]:
        return [r for r in self.requetes if r.url.host == "gmail.googleapis.com"]

    def __call__(self, r: httpx.Request) -> httpx.Response:
        self.requetes.append(r)
        if r.url.host == "oauth2.googleapis.com" and r.url.path == "/token":
            d = {k: v[0] for k, v in parse_qs(r.content.decode()).items()}
            if d.get("grant_type") == "authorization_code":
                if d.get("code") != "code-ok" or not d.get("code_verifier"):
                    return httpx.Response(400, json={"error": "invalid_grant"})
                return httpx.Response(200, json={"access_token": "at-1", "expires_in": 3599,
                                                 "refresh_token": self.rafraichissement, "scope": self.portee,
                                                 "token_type": "Bearer"})
            if self.refus_rafraichissement:
                return httpx.Response(400, json={"error": self.refus_rafraichissement})
            return httpx.Response(200, json={"access_token": "at-2", "expires_in": 3599})
        if r.url.host == "oauth2.googleapis.com" and r.url.path == "/revoke":
            self.revoques.append(parse_qs(r.content.decode())["token"][0])
            return httpx.Response(200)
        if r.url.host == "gmail.googleapis.com":
            if self.acces_expire_une_fois and r.headers["authorization"] == "Bearer at-1":
                self.acces_expire_une_fois = False
                return httpx.Response(401, json={"error": {"code": 401}})
            if self.statut_gmail:
                return httpx.Response(self.statut_gmail, text="insufficientPermissions scope")
            chemin = r.url.path.removeprefix("/gmail/v1/users/me/")
            if chemin == "profile":
                return httpx.Response(200, json={"emailAddress": self.email})
            if chemin == "messages":
                self.recherches.append(r.url.params["q"])
                if self.panne_recherche is not None:
                    raise self.panne_recherche
                n = int(r.url.params.get("maxResults", 5))
                ids = [i for i in self.messages if not self.filtrer or correspond(r.url.params["q"], self.messages[i])]
                if self.filtrer:
                    ids.sort(key=lambda i: _epoch(self.messages[i]), reverse=True)      # plus récents d'abord
                total = len(ids)
                suite = total > n             # comme Gmail : jeton de page suivante
                ids = ids[:n]
                corps = {"messages": [{"id": i, "threadId": self.messages[i]["threadId"]} for i in ids]}                     if ids else {"resultSizeEstimate": 0}
                if suite:
                    corps["nextPageToken"] = "page2"
                    corps["resultSizeEstimate"] = total      # Gmail : estimation
                return httpx.Response(200, json=corps)
            if chemin == "labels/INBOX":
                boite = [m for m in self.messages.values() if "INBOX" in m["labelIds"]]
                non_lus = [m for m in boite if "UNREAD" in m["labelIds"]]
                return httpx.Response(200, json={"id": "INBOX", "messagesUnread": len(non_lus),
                                                 "threadsUnread": len({m["threadId"] for m in non_lus})})
            if "/attachments/" in chemin:
                d = self.corps_charges.get(chemin.split("/")[-1])
                return httpx.Response(200, json={"data": d}) if d else httpx.Response(404)
            if chemin.startswith("messages/"):
                m = self.messages.get(chemin.split("/")[1])
                return httpx.Response(200, json=m) if m else httpx.Response(404)
            if chemin.startswith("threads/"):
                fil = chemin.split("/")[1]
                ms = [m for m in self.messages.values() if m["threadId"] == fil]
                return httpx.Response(200, json={"id": fil, "messages": ms}) if ms else httpx.Response(404)
        return httpx.Response(404)


class FauxConnexions:
    """Stockage des connexions (fonctions SQL simulées, jeton « dans Vault »)."""

    def __init__(self) -> None:
        self.lignes: dict[tuple[str, str], dict] = {}

    async def enregistrer_connexion(self, user_id, provider, email, scopes, jeton):
        self.lignes[(user_id, provider)] = {"connexion_id": "c1", "account_email": email.lower(), "scopes": scopes,
                                            "status": "active", "jeton": jeton, "connected_at": "2026-10-18T10:00:00Z",
                                            "last_used_at": None, "last_error": None}
        return "c1"

    async def jeton_connexion(self, user_id, provider):
        return self.lignes.get((user_id, provider))

    async def etat_connexion(self, user_id, provider):
        l = self.lignes.get((user_id, provider))
        return None if l is None else {k: v for k, v in l.items() if k not in ("jeton", "connexion_id")}

    async def marquer_connexion(self, user_id, provider, status, erreur=None):
        if (user_id, provider) in self.lignes:
            self.lignes[(user_id, provider)].update(status=status, last_error=erreur)

    async def supprimer_connexion(self, user_id, provider):
        return self.lignes.pop((user_id, provider), None) is not None


def service_google(settings, redis, connexions: FauxConnexions, google: FauxGoogle) -> ServiceGoogle:
    s = settings.model_copy(update={"google_client_id": "client-test.apps.googleusercontent.com",
                                    "google_client_secret": "secret-client-test",
                                    "google_redirect_uri": "http://localhost:8001/api/v1/integrations/gmail/retour"})
    return ServiceGoogle(s, redis, connexions, http=httpx.AsyncClient(transport=httpx.MockTransport(google)))


def json_corps(r: httpx.Response) -> dict:
    return json.loads(r.text)


# --- Évaluation (simplifiée) d'une requête Gmail ---------------------------------------

def _entete(m: dict, nom: str) -> str:
    return next((h["value"] for h in m["payload"]["headers"] if h["name"] == nom), "")


def _epoch(m: dict) -> int:
    return int(parsedate_to_datetime(_entete(m, "Date")).timestamp())


def _texte(m: dict) -> str:
    morceaux = []
    for p in m["payload"].get("parts", []):
        if p["mimeType"].startswith("text/") and p["body"].get("data"):
            d = p["body"]["data"]
            morceaux.append(base64.urlsafe_b64decode(d + "=" * (-len(d) % 4)).decode())
    return " ".join(morceaux)


def _terme(t: str, m: dict) -> bool:
    if ":" in t and not t.startswith('"'):
        op, _, v = t.partition(":")
        v = v.strip('"').lower()
        match op:
            case "from":
                return v in _entete(m, "From").lower()
            case "to":
                return v in _entete(m, "To").lower()
            case "subject":
                return v in _entete(m, "Subject").lower()
            case "after":
                return _epoch(m) >= int(v)
            case "before":
                return _epoch(m) < int(v)
            case "has":
                return any(p.get("filename") for p in m["payload"].get("parts", []))
            case "is":
                return {"unread": "UNREAD", "important": "IMPORTANT"}[v] in m["labelIds"]
            case "in":
                return v != "sent" or "SENT" in m["labelIds"]
        return False
    v = t.strip('"').lower()
    return v in (_entete(m, "Subject") + " " + _entete(m, "From") + " " + _texte(m)).lower()


def correspond(q: str, m: dict) -> bool:
    for morceau in re.findall(r'\{[^}]*\}|\S+:"[^"]*"|"[^"]*"|\S+', q):
        if morceau.startswith("{"):
            if not any(_terme(t, m) for t in re.findall(r'\S+:"[^"]*"|"[^"]*"|\S+', morceau[1:-1])):
                return False
        elif not _terme(morceau, m):
            return False
    return True
