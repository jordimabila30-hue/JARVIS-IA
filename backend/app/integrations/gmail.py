"""Lecture Gmail (API REST v1, portée gmail.readonly).

Uniquement des requêtes GET : rechercher, lire un message, lire un fil.
Aucune écriture (ni envoi, ni suppression, ni libellé, ni « lu »).
Coûts bornés : nombre de résultats, messages d'un fil, taille du texte ;
les pièces jointes ne sont jamais téléchargées (seulement leur nom).
Un jeton expiré est renouvelé une fois ; une autorisation retirée chez
Google rend la connexion « à renouveler ».
"""

from __future__ import annotations

import asyncio
import base64
import html
import re
from dataclasses import dataclass, field
from datetime import date, timedelta

import httpx

from .google import ConnexionARenouveler, ErreurGoogle, ServiceGoogle

API = "https://gmail.googleapis.com/gmail/v1/users/me"
ENTETES = ("From", "To", "Subject", "Date")
_ID = re.compile(r"^[A-Za-z0-9_-]{6,64}$")
_INTERDITS = re.compile(r'["(){}\[\]:<>\\]')


@dataclass
class ApercuEmail:
    id: str
    fil: str
    de: str
    objet: str
    date: str
    extrait: str
    non_lu: bool = False
    important: bool = False


@dataclass
class Email(ApercuEmail):
    a: str = ""
    texte: str = ""
    pieces_jointes: list[str] = field(default_factory=list)
    tronque: bool = False


def valeur_requete(texte: str) -> str:
    """Valeur sûre pour la syntaxe de recherche Gmail (guillemets, opérateurs retirés)."""
    return " ".join(_INTERDITS.sub(" ", texte).split())[:150]


def construire_requete(*, expediteur: str | None = None, objet: str | None = None, mots: str | None = None,
                       depuis: date | None = None, jusqua: date | None = None,
                       non_lus: bool = False, importants: bool = False) -> str:
    """Requête Gmail (`q`) à partir de critères structurés, jamais d'une
    chaîne libre du modèle."""
    morceaux = []
    if expediteur and valeur_requete(expediteur):
        morceaux.append(f'from:"{valeur_requete(expediteur)}"')
    if objet and valeur_requete(objet):
        morceaux.append(f'subject:"{valeur_requete(objet)}"')
    if mots and valeur_requete(mots):
        morceaux.append(valeur_requete(mots))
    if depuis:
        morceaux.append(f"after:{depuis:%Y/%m/%d}")
    if jusqua:
        morceaux.append(f"before:{jusqua + timedelta(days=1):%Y/%m/%d}")     # jusqu'à ce jour inclus
    if non_lus:
        morceaux.append("is:unread")
    if importants:
        morceaux.append("is:important")
    return " ".join(morceaux) or "in:inbox"


def _entetes(message: dict) -> dict[str, str]:
    return {h.get("name", ""): h.get("value", "") for h in (message.get("payload") or {}).get("headers") or []}


def _decoder(donnees: str | None) -> str:
    if not donnees:
        return ""
    try:
        return base64.urlsafe_b64decode(donnees + "=" * (-len(donnees) % 4)).decode("utf-8", errors="replace")
    except (ValueError, TypeError):
        return ""


_BALISES = re.compile(r"<(script|style)[^>]*>.*?</\1>|<[^>]+>", re.S | re.I)


def _texte_html(contenu: str) -> str:
    contenu = re.sub(r"<\s*(br|/p|/div|/li|/tr)[^>]*>", "\n", contenu, flags=re.I)
    return html.unescape(_BALISES.sub(" ", contenu))


def extraire(payload: dict) -> tuple[str, list[str]]:
    """Texte lisible (text/plain de préférence, sinon HTML nettoyé) et noms
    des pièces jointes (jamais leur contenu)."""
    plain, html_, pieces = [], [], []

    def parcourir(p: dict) -> None:
        mime = p.get("mimeType", "")
        nom = p.get("filename") or ""
        corps = p.get("body") or {}
        if nom and (corps.get("attachmentId") or not mime.startswith("text/")):
            pieces.append(nom[:120])
        elif mime == "text/plain":
            plain.append(_decoder(corps.get("data")))
        elif mime == "text/html":
            html_.append(_decoder(corps.get("data")))
        for sous in p.get("parts") or []:
            parcourir(sous)

    parcourir(payload or {})
    texte = "\n".join(plain) if any(t.strip() for t in plain) else _texte_html("\n".join(html_))
    texte = re.sub(r"[ \t\r\f\v]+", " ", texte)
    texte = re.sub(r"\n\s*\n+", "\n\n", texte).strip()
    return texte, pieces


def _apercu(m: dict) -> ApercuEmail:
    e = _entetes(m)
    libelles = m.get("labelIds") or []
    return ApercuEmail(id=m.get("id", ""), fil=m.get("threadId", ""), de=e.get("From", "")[:200],
                       objet=e.get("Subject", "")[:300], date=e.get("Date", "")[:80],
                       extrait=html.unescape(m.get("snippet", ""))[:300],
                       non_lu="UNREAD" in libelles, important="IMPORTANT" in libelles)


def _email(m: dict, maximum: int) -> Email:
    a = _apercu(m)
    texte, pieces = extraire(m.get("payload") or {})
    tronque = len(texte) > maximum
    return Email(**a.__dict__, a=_entetes(m).get("To", "")[:300], texte=texte[:maximum],
                 pieces_jointes=pieces[:10], tronque=tronque)


class ClientGmail:
    def __init__(self, google: ServiceGoogle, http: httpx.AsyncClient | None = None) -> None:
        self.google = google
        # Même client HTTP que la connexion Google (délai commun, un seul pool).
        self._http = http or google.http

    async def _get(self, user_id: str, chemin: str, params: dict | list | None = None) -> dict:
        """GET authentifié (seule méthode HTTP utilisée vers Gmail)."""
        for essai in range(2):
            jeton = await self.google.jeton_acces(user_id, forcer=essai > 0)
            try:
                r = await self._http.get(f"{API}/{chemin}", params=params,
                                         headers={"Authorization": f"Bearer {jeton}"})
            except httpx.HTTPError:
                raise ErreurGoogle("reseau") from None
            if r.status_code == 401 and essai == 0:
                continue                                   # jeton expiré : renouvelé une fois
            if r.status_code == 401:
                raise ConnexionARenouveler()
            if r.status_code == 403:
                corps = r.text.lower()
                if "insufficient" in corps or "scope" in corps:
                    await self.google._supabase.marquer_connexion(user_id, "gmail", "a_renouveler", "portee")
                    raise ConnexionARenouveler("portee")
                raise ErreurGoogle("limite_google" if "rate" in corps or "quota" in corps else "refuse")
            if r.status_code == 404:
                raise ErreurGoogle("introuvable")
            if r.status_code == 429:
                raise ErreurGoogle("limite_google")
            if r.status_code >= 400:
                raise ErreurGoogle("temporaire")
            return r.json()
        raise ConnexionARenouveler()

    async def rechercher(self, user_id: str, requete: str, maximum: int) -> list[ApercuEmail]:
        liste = await self._get(user_id, "messages", {"q": requete, "maxResults": maximum})
        ids = [m["id"] for m in (liste.get("messages") or [])[:maximum] if _ID.match(m.get("id", ""))]
        params = [("format", "metadata")] + [("metadataHeaders", h) for h in ENTETES]
        details = await asyncio.gather(*(self._get(user_id, f"messages/{i}", params) for i in ids))
        return [_apercu(m) for m in details]

    async def message(self, user_id: str, message_id: str, maximum: int) -> Email:
        if not _ID.match(message_id):
            raise ErreurGoogle("introuvable")
        return _email(await self._get(user_id, f"messages/{message_id}", {"format": "full"}), maximum)

    async def fil(self, user_id: str, fil_id: str, maximum_messages: int, maximum: int) -> list[Email]:
        if not _ID.match(fil_id):
            raise ErreurGoogle("introuvable")
        d = await self._get(user_id, f"threads/{fil_id}", {"format": "full"})
        messages = (d.get("messages") or [])[-maximum_messages:]
        return [_email(m, maximum) for m in messages]

