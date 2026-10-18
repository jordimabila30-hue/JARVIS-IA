"""Connexion Google pour Gmail (OAuth 2.0, côté serveur, lecture seule).

Flux « authorization code » + PKCE (S256) + `state` à usage unique :
  1. l'application (utilisateur JARVIS authentifié, JWT) demande une URL :
     `state` aléatoire et vérificateur PKCE gardés dans Redis 10 min,
     liés au compte JARVIS ;
  2. le navigateur du système ouvre Google (choix du compte, consentement :
     `prompt=select_account consent`) ;
  3. Google renvoie vers `GOOGLE_REDIRECT_URI` (ce serveur) : `state`
     consommé (GETDEL), code échangé avec le vérificateur PKCE et le secret
     client, portée vérifiée (gmail.readonly), adresse lue (profil Gmail) ;
  4. jeton de rafraîchissement chiffré dans Supabase Vault ; jeton d'accès
     seulement en mémoire, renouvelé à l'échéance.
Aucun jeton n'est renvoyé à l'application, au modèle ni aux journaux.
Changer de compte : nouveau consentement complet ; l'ancien jeton est
révoqué chez Google puis écrasé.
"""

from __future__ import annotations

import base64
import hashlib
import json
import logging
import secrets
import time
from dataclasses import dataclass
from urllib.parse import urlencode

import httpx
from redis.asyncio import Redis

from ..config import Settings
from ..supabase_client import SupabaseAdmin

logger = logging.getLogger(__name__)

PORTEE_GMAIL = "https://www.googleapis.com/auth/gmail.readonly"
URL_AUTORISATION = "https://accounts.google.com/o/oauth2/v2/auth"
URL_JETON = "https://oauth2.googleapis.com/token"
URL_REVOCATION = "https://oauth2.googleapis.com/revoke"
URL_PROFIL = "https://gmail.googleapis.com/gmail/v1/users/me/profile"
FOURNISSEUR = "gmail"
DUREE_ETAT = 600
PLATEFORMES = ("android", "windows", "web", "ios", "autre")


def cle_etat(state: str) -> str:
    return f"gmail:etat:{state}"


def defi_pkce(verificateur: str) -> str:
    return base64.urlsafe_b64encode(hashlib.sha256(verificateur.encode()).digest()).rstrip(b"=").decode()


class ErreurGoogle(Exception):
    """`code` court (jamais de jeton ni de réponse brute de Google)."""

    def __init__(self, code: str) -> None:
        self.code = code
        super().__init__(code)


class ConnexionARenouveler(ErreurGoogle):
    def __init__(self, code: str = "a_renouveler") -> None:
        super().__init__(code)


class NonConnecte(ErreurGoogle):
    def __init__(self) -> None:
        super().__init__("non_connecte")


@dataclass(frozen=True)
class ResultatRetour:
    ok: bool
    code: str                     # connecte | annule | expire | refuse | portee | erreur
    plateforme: str = "autre"
    email: str | None = None


@dataclass
class _JetonAcces:
    valeur: str
    echeance: float               # time.monotonic()
    email: str


class ServiceGoogle:
    def __init__(self, settings: Settings, redis: Redis, supabase: SupabaseAdmin,
                 http: httpx.AsyncClient | None = None) -> None:
        self.settings = settings
        self._redis = redis
        self._supabase = supabase
        self._http = http or httpx.AsyncClient(timeout=settings.gmail_delai)
        self._acces: dict[str, _JetonAcces] = {}

    @property
    def http(self) -> httpx.AsyncClient:
        return self._http

    @property
    def configure(self) -> bool:
        s = self.settings
        return bool(s.google_client_id and s.google_client_secret and s.google_redirect_uri)

    # --- 1. URL d'autorisation ---------------------------------------------------

    async def url_autorisation(self, user_id: str, plateforme: str) -> str:
        if not self.configure:
            raise ErreurGoogle("non_configure")
        state = secrets.token_urlsafe(32)
        verificateur = secrets.token_urlsafe(64)
        await self._redis.set(cle_etat(state), json.dumps({
            "user_id": user_id, "verificateur": verificateur,
            "plateforme": plateforme if plateforme in PLATEFORMES else "autre",
        }), ex=DUREE_ETAT)
        return URL_AUTORISATION + "?" + urlencode({
            "client_id": self.settings.google_client_id,
            "redirect_uri": self.settings.google_redirect_uri,
            "response_type": "code",
            "scope": PORTEE_GMAIL,
            "access_type": "offline",
            "prompt": "select_account consent",
            "include_granted_scopes": "false",
            "state": state,
            "code_challenge": defi_pkce(verificateur),
            "code_challenge_method": "S256",
        })

    # --- 2-3. Retour de Google ---------------------------------------------------

    async def retour(self, *, state: str | None, code: str | None, erreur: str | None) -> ResultatRetour:
        if not state or len(state) > 200:
            return ResultatRetour(False, "expire")
        brut = await self._redis.getdel(cle_etat(state))
        if not brut:
            return ResultatRetour(False, "expire")            # inconnu, expiré ou déjà utilisé
        etat = json.loads(brut)
        plateforme = etat.get("plateforme", "autre")
        if erreur:
            return ResultatRetour(False, "annule" if erreur == "access_denied" else "refuse", plateforme)
        if not code:
            return ResultatRetour(False, "erreur", plateforme)
        try:
            jetons = await self._echanger(code, etat["verificateur"])
        except ErreurGoogle as exc:
            return ResultatRetour(False, exc.code, plateforme)
        portees = (jetons.get("scope") or "").split()
        if PORTEE_GMAIL not in portees:
            # Consentement partiel : la lecture Gmail n'a pas été accordée.
            await self._revoquer(jetons.get("refresh_token") or jetons.get("access_token"))
            return ResultatRetour(False, "portee", plateforme)
        rafraichissement = jetons.get("refresh_token")
        if not rafraichissement:
            return ResultatRetour(False, "erreur", plateforme)
        try:
            email = await self._email(jetons["access_token"])
        except ErreurGoogle as exc:
            await self._revoquer(rafraichissement)
            return ResultatRetour(False, exc.code, plateforme)
        user_id = etat["user_id"]
        ancienne = await self._supabase.jeton_connexion(user_id, FOURNISSEUR)
        if ancienne and ancienne.get("jeton") and ancienne["jeton"] != rafraichissement:
            # Autre compte (ou nouveau consentement) : l'ancien accès est retiré chez Google.
            await self._revoquer(ancienne["jeton"])
        await self._supabase.enregistrer_connexion(user_id, FOURNISSEUR, email, [PORTEE_GMAIL], rafraichissement)
        self._acces[user_id] = _JetonAcces(jetons["access_token"],
                                           time.monotonic() + int(jetons.get("expires_in") or 3000) - 60, email)
        logger.info("Gmail connecté (plateforme=%s)", plateforme)
        return ResultatRetour(True, "connecte", plateforme, email)

    async def _echanger(self, code: str, verificateur: str) -> dict:
        try:
            r = await self._http.post(URL_JETON, data={
                "code": code, "client_id": self.settings.google_client_id,
                "client_secret": self.settings.google_client_secret,
                "redirect_uri": self.settings.google_redirect_uri,
                "grant_type": "authorization_code", "code_verifier": verificateur,
            })
        except httpx.HTTPError:
            raise ErreurGoogle("reseau") from None
        if r.status_code != 200:
            logger.warning("Échange du code Google refusé (HTTP %d)", r.status_code)
            raise ErreurGoogle("refuse")
        return r.json()

    async def _email(self, acces: str) -> str:
        try:
            r = await self._http.get(URL_PROFIL, headers={"Authorization": f"Bearer {acces}"})
        except httpx.HTTPError:
            raise ErreurGoogle("reseau") from None
        if r.status_code != 200:
            raise ErreurGoogle("refuse")
        email = (r.json() or {}).get("emailAddress")
        if not email:
            raise ErreurGoogle("erreur")
        return email

    async def _revoquer(self, jeton: str | None) -> None:
        if not jeton:
            return
        try:
            await self._http.post(URL_REVOCATION, data={"token": jeton})
        except httpx.HTTPError:
            logger.warning("Révocation Google impossible (réseau)")

    # --- État, déconnexion ------------------------------------------------------

    async def etat(self, user_id: str) -> dict:
        ligne = await self._supabase.etat_connexion(user_id, FOURNISSEUR)
        if ligne is None:
            return {"statut": "non_connecte", "configure": self.configure}
        return {
            "statut": "connecte" if ligne["status"] == "active" else "a_renouveler",
            "configure": self.configure,
            "email": ligne["account_email"],
            "portee": "lecture_seule" if ligne.get("scopes") == [PORTEE_GMAIL] else "inconnue",
            "connecte_le": ligne.get("connected_at"),
            "derniere_utilisation": ligne.get("last_used_at"),
        }

    async def statut(self, user_id: str) -> str | None:
        """'active', 'a_renouveler' ou None (non connecté)."""
        ligne = await self._supabase.etat_connexion(user_id, FOURNISSEUR)
        return ligne["status"] if ligne else None

    async def deconnecter(self, user_id: str) -> bool:
        """Accès coupé immédiatement : jeton d'accès oublié, révocation chez
        Google, ligne et secret Vault supprimés. La boîte Gmail n'est pas touchée."""
        self._acces.pop(user_id, None)
        ancienne = await self._supabase.jeton_connexion(user_id, FOURNISSEUR)
        if ancienne and ancienne.get("jeton"):
            await self._revoquer(ancienne["jeton"])
        return await self._supabase.supprimer_connexion(user_id, FOURNISSEUR)

    # --- Jeton d'accès (outils Gmail) -------------------------------------------

    async def jeton_acces(self, user_id: str, *, forcer: bool = False) -> str:
        """Jeton d'accès valide pour CE compte (renouvelé si besoin). Lève
        NonConnecte / ConnexionARenouveler / ErreurGoogle."""
        en_cache = self._acces.get(user_id)
        if en_cache and not forcer and en_cache.echeance > time.monotonic():
            return en_cache.valeur
        ligne = await self._supabase.jeton_connexion(user_id, FOURNISSEUR)
        if ligne is None or not ligne.get("jeton"):
            raise NonConnecte()
        if ligne["status"] != "active":
            raise ConnexionARenouveler()
        try:
            r = await self._http.post(URL_JETON, data={
                "client_id": self.settings.google_client_id,
                "client_secret": self.settings.google_client_secret,
                "refresh_token": ligne["jeton"], "grant_type": "refresh_token",
            })
        except httpx.HTTPError:
            raise ErreurGoogle("reseau") from None
        if r.status_code in (400, 401):
            code = (r.json() if r.headers.get("content-type", "").startswith("application/json") else {}).get("error")
            if code in ("invalid_grant", "unauthorized_client", "invalid_client"):
                # Révoqué ou expiré chez Google : l'utilisateur doit se reconnecter.
                self._acces.pop(user_id, None)
                await self._supabase.marquer_connexion(user_id, FOURNISSEUR, "a_renouveler", code)
                raise ConnexionARenouveler()
        if r.status_code != 200:
            raise ErreurGoogle("temporaire")
        d = r.json()
        self._acces[user_id] = _JetonAcces(d["access_token"],
                                           time.monotonic() + int(d.get("expires_in") or 3000) - 60,
                                           ligne["account_email"])
        return d["access_token"]

    def oublier(self, user_id: str) -> None:
        self._acces.pop(user_id, None)

    async def fermer(self) -> None:
        await self._http.aclose()


_service: ServiceGoogle | None = None


def init_google(settings: Settings, redis: Redis, supabase: SupabaseAdmin) -> ServiceGoogle:
    global _service
    _service = ServiceGoogle(settings, redis, supabase)
    return _service


def get_google() -> ServiceGoogle:
    if _service is None:
        raise RuntimeError("ServiceGoogle non initialisé")
    return _service


async def close_google() -> None:
    global _service
    if _service is not None:
        await _service.fermer()
        _service = None
