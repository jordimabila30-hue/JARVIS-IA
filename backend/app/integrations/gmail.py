"""Lecture Gmail (API REST v1, portée gmail.readonly).

Uniquement des requêtes GET : rechercher, lire un message, lire un fil.
Aucune écriture (ni envoi, ni suppression, ni libellé, ni « lu »).
Coûts bornés : nombre de résultats, messages d'un fil, taille du texte ;
les pièces jointes ne sont jamais téléchargées (seulement leur nom) ; un gros
corps texte ou HTML (rangé par Gmail comme `attachmentId`) est lu, ce n'est
pas une pièce jointe.
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


class Trouves(list):
    """Résultats d'une recherche ; [suite] : Gmail en a d'autres au-delà
    (la longueur n'est alors qu'un minimum, jamais un total)."""

    def __init__(self, elements=(), *, suite: bool = False, estimation: int | None = None):
        super().__init__(elements)
        self.suite = suite
        # resultSizeEstimate de Gmail : une ESTIMATION, jamais un total exact.
        self.estimation = estimation


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


def _charset(partie: dict) -> str:
    for h in partie.get("headers") or []:
        if h.get("name", "").lower() == "content-type":
            m = re.search(r'charset="?([A-Za-z0-9_.:-]+)', h.get("value", ""), re.I)
            if m:
                return m.group(1)
    return "utf-8"


def _decoder(donnees: str | None, charset: str = "utf-8") -> str:
    if not donnees:
        return ""
    try:
        brut = base64.urlsafe_b64decode(donnees + "=" * (-len(donnees) % 4))
    except (ValueError, TypeError):
        return ""
    try:
        return brut.decode(charset, errors="replace")
    except LookupError:                     # jeu de caractères inconnu
        return brut.decode("utf-8", errors="replace")


_BALISES = re.compile(r"<!--.*?-->|<(script|style|head|title|noscript)\b[^>]*>.*?</\1\s*>|<[^>]+>", re.S | re.I)
_BLOCS = re.compile(r"<\s*(?:br|/?p|/?div|/?li|/?tr|/?h[1-6]|/?table|/?ul|/?ol|/?blockquote|hr)\b[^>]*>", re.I)


def _texte_html(contenu: str) -> str:
    contenu = _BLOCS.sub("\n", contenu)
    contenu = re.sub(r"<\s*/?t[dh]\b[^>]*>", " ", contenu, flags=re.I)
    texte = html.unescape(_BALISES.sub(" ", contenu)).replace(" ", " ").replace("‌", "")
    return texte


def _utile(texte: str) -> int:
    return len(re.sub(r"\s+", "", texte))


def _parties(payload: dict) -> tuple[list[str], list[str], list[str], list[tuple[str, str]]]:
    """(textes plain, textes HTML, pièces jointes, corps texte à télécharger :
    (type, attachmentId) — Gmail ne joint pas les gros corps au message)."""
    plain, html_, pieces, a_charger = [], [], [], []

    def parcourir(p: dict) -> None:
        mime = (p.get("mimeType") or "").lower()
        nom = p.get("filename") or ""
        corps = p.get("body") or {}
        if nom and (corps.get("attachmentId") or not mime.startswith("text/")):
            pieces.append(nom[:120])
        elif mime in ("text/plain", "text/html"):
            if corps.get("data"):
                (plain if mime == "text/plain" else html_).append(_decoder(corps.get("data"), _charset(p)))
            elif corps.get("attachmentId"):
                a_charger.append((mime, corps["attachmentId"]))
        for sous in p.get("parts") or []:
            parcourir(sous)

    parcourir(payload or {})
    return plain, html_, pieces, a_charger


def _assembler(plain: list[str], html_: list[str]) -> str:
    """text/plain de préférence ; HTML si le texte brut manque ou n'est
    qu'un reste (« votre messagerie n'affiche pas le HTML », lien seul…)."""
    texte_plain = "\n".join(plain)
    texte_html = _texte_html("\n".join(html_)) if html_ else ""
    if _utile(texte_html) > max(2 * _utile(texte_plain), _utile(texte_plain) + 60):
        texte = texte_html
    else:
        texte = texte_plain if _utile(texte_plain) else texte_html
    texte = re.sub(r"[ \t\r\f\v]+", " ", texte)
    texte = re.sub(r" *\n *", "\n", texte)
    return re.sub(r"\n{3,}", "\n\n", texte).strip()


def extraire(payload: dict) -> tuple[str, list[str]]:
    """Texte lisible et noms des pièces jointes (jamais leur contenu)."""
    plain, html_, pieces, _ = _parties(payload)
    return _assembler(plain, html_), pieces


def _apercu(m: dict) -> ApercuEmail:
    e = _entetes(m)
    libelles = m.get("labelIds") or []
    return ApercuEmail(id=m.get("id", ""), fil=m.get("threadId", ""), de=e.get("From", "")[:200],
                       objet=e.get("Subject", "")[:300], date=e.get("Date", "")[:80],
                       extrait=html.unescape(m.get("snippet", ""))[:300],
                       non_lu="UNREAD" in libelles, important="IMPORTANT" in libelles)


def _email(m: dict, maximum: int, charges: list[tuple[str, str]] = ()) -> Email:
    a = _apercu(m)
    plain, html_, pieces, _ = _parties(m.get("payload") or {})
    for mime, contenu in charges:
        (plain if mime == "text/plain" else html_).append(contenu)
    texte = _assembler(plain, html_)
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

    async def rechercher(self, user_id: str, requete: str, maximum: int) -> "Trouves":
        liste = await self._get(user_id, "messages", {"q": requete, "maxResults": maximum})
        ids = [m["id"] for m in (liste.get("messages") or [])[:maximum] if _ID.match(m.get("id", ""))]
        params = [("format", "metadata")] + [("metadataHeaders", h) for h in ENTETES]
        details = await asyncio.gather(*(self._get(user_id, f"messages/{i}", params) for i in ids))
        # Page suivante annoncée par Gmail : la liste n'est PAS complète.
        estimation = liste.get("resultSizeEstimate")
        return Trouves([_apercu(m) for m in details], suite=bool(liste.get("nextPageToken")),
                       estimation=int(estimation) if isinstance(estimation, int) else None)

    async def non_lus(self, user_id: str) -> tuple[int, int]:
        """Compteurs EXACTS de Gmail pour la boîte de réception : (conversations
        non lues, messages non lus). Aucune liste parcourue, aucune estimation."""
        d = await self._get(user_id, "labels/INBOX")
        return int(d.get("threadsUnread") or 0), int(d.get("messagesUnread") or 0)

    async def message(self, user_id: str, message_id: str, maximum: int) -> Email:
        if not _ID.match(message_id):
            raise ErreurGoogle("introuvable")
        return await self._complet(user_id, await self._get(user_id, f"messages/{message_id}", {"format": "full"}),
                                   maximum)

    async def _complet(self, user_id: str, m: dict, maximum: int) -> Email:
        """Message lu, gros corps texte/HTML compris (téléchargés : ce ne sont
        pas des pièces jointes) ; jamais plus de 2 corps."""
        a_charger = _parties(m.get("payload") or {})[3][:2]
        charges = []
        for mime, piece in a_charger:
            if not _ID.match(m.get("id", "")) or not re.fullmatch(r"[A-Za-z0-9_-]{6,1024}", piece):
                continue
            try:
                d = await self._get(user_id, f"messages/{m['id']}/attachments/{piece}")
            except ErreurGoogle:
                continue
            charges.append((mime, _decoder(d.get("data"))))
        return _email(m, maximum, charges)

    async def fil(self, user_id: str, fil_id: str, maximum_messages: int, maximum: int) -> list[Email]:
        if not _ID.match(fil_id):
            raise ErreurGoogle("introuvable")
        d = await self._get(user_id, f"threads/{fil_id}", {"format": "full"})
        messages = (d.get("messages") or [])[-maximum_messages:]
        return list(await asyncio.gather(*(self._complet(user_id, m, maximum) for m in messages)))

