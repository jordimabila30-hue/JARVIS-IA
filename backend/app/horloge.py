"""Surveillance de l'horloge du serveur.

Les jetons Supabase sont vérifiés avec une tolérance de quelques secondes
(`TOLERANCE_JWT_SECONDES`). Si l'horloge de la machine qui exécute l'API
dérive au-delà, chaque jeton paraît « émis dans le futur » (ou déjà expiré)
et il est refusé : « Token invalide ». Ce module mesure cet écart et le
signale clairement dans les journaux, sans rien corriger lui-même.

Référence : l'en-tête HTTP `Date` du serveur qui émet les jetons (Supabase
Auth par défaut). Aucun NTP dans le conteneur : un conteneur partage
l'horloge de sa machine hôte, c'est elle qu'il faut synchroniser (Windows
Time sous Docker Desktop ; chrony / systemd-timesyncd sur un serveur
Linux). La précision (±1 s environ) suffit largement pour un seuil de
plusieurs secondes.

Non destructif : une mesure ratée ne fait qu'un avertissement ; rien
n'est bloqué, ni le démarrage ni les requêtes.
"""

from __future__ import annotations

import asyncio
import logging
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from urllib.parse import urlsplit

import httpx

logger = logging.getLogger(__name__)

# Tolérance appliquée à la vérification des JWT (`exp`, `iat`, `nbf`).
# Ne pas l'augmenter pour masquer une horloge déréglée.
TOLERANCE_JWT_SECONDES = 10


@dataclass(frozen=True)
class MesureHorloge:
    """Écart entre l'horloge de référence et celle de ce serveur.

    `ecart` > 0 : ce serveur est en retard ; < 0 : en avance.
    """

    ecart: float
    incertitude: float
    mesure_le: datetime
    reference: str


async def mesurer_ecart(client: httpx.AsyncClient, url: str) -> MesureHorloge:
    """Une mesure : l'heure de la référence (en-tête `Date`) comparée à
    l'heure locale au milieu de l'aller-retour. Lève `httpx.HTTPError` si
    la référence est injoignable, `ValueError` si l'en-tête manque."""
    debut = time.time()
    # Peu importe le statut (401 sans clé, 404…) : seul l'en-tête compte.
    reponse = await client.get(url)
    fin = time.time()
    date = reponse.headers.get("date")
    if not date:
        raise ValueError("la référence ne fournit pas d'en-tête Date")
    reference = parsedate_to_datetime(date).timestamp()
    # `Date` est à la seconde près (tronquée) : milieu de la seconde.
    ecart = (reference + 0.5) - (debut + fin) / 2
    incertitude = (fin - debut) / 2 + 0.5
    return MesureHorloge(
        ecart=ecart,
        incertitude=incertitude,
        mesure_le=datetime.now(timezone.utc),
        reference=urlsplit(url).hostname or url,
    )


class SurveillanceHorloge:
    """Mesure l'écart au démarrage puis à intervalle régulier, et le
    journalise : INFO si tout va bien, WARNING au-delà du seuil d'alerte,
    ERROR au-delà de la tolérance des jetons."""

    def __init__(
        self,
        url: str,
        *,
        seuil_alerte: float = 5.0,
        intervalle: int = 900,
        client: httpx.AsyncClient | None = None,
    ) -> None:
        self.url = url
        self.seuil_alerte = seuil_alerte
        self.intervalle = intervalle
        self._client = client or httpx.AsyncClient(timeout=10.0)
        self._client_interne = client is None
        self._tache: asyncio.Task | None = None
        self.derniere: MesureHorloge | None = None
        self.erreur: str | None = None

    @property
    def active(self) -> bool:
        return self.intervalle > 0

    def etat(self) -> str:
        """« desactivee », « inconnu », « ok », « decale » ou « critique »."""
        if not self.active:
            return "desactivee"
        m = self.derniere
        if m is None:
            return "inconnu"
        # Critique seulement si l'écart dépasse la tolérance même dans le
        # cas le plus favorable de la mesure.
        if abs(m.ecart) - m.incertitude > TOLERANCE_JWT_SECONDES:
            return "critique"
        if abs(m.ecart) > self.seuil_alerte:
            return "decale"
        return "ok"

    async def verifier(self) -> MesureHorloge | None:
        """Une vérification (jamais d'exception)."""
        try:
            mesure = await mesurer_ecart(self._client, self.url)
        except (httpx.HTTPError, ValueError) as exc:
            self.erreur = f"{type(exc).__name__}: {exc}"
            logger.warning(
                "Horloge : mesure impossible auprès de %s (%s). L'écart avec "
                "le serveur des jetons n'est pas surveillé pour l'instant.",
                urlsplit(self.url).hostname or self.url,
                type(exc).__name__,
            )
            return None
        self.derniere = mesure
        self.erreur = None
        self._journaliser(mesure)
        return mesure

    def _journaliser(self, m: MesureHorloge) -> None:
        sens = "en retard" if m.ecart > 0 else "en avance"
        ecart = f"{abs(m.ecart):.1f} s (±{m.incertitude:.1f} s)"
        etat = self.etat()
        if etat == "critique":
            logger.error(
                "Horloge du serveur %s de %s sur %s : au-delà de la tolérance "
                "des jetons (%d s), les jetons Supabase sont refusés (« Token "
                "invalide »). Synchronisez l'heure de la machine hôte (Windows "
                "Time sous Docker Desktop ; chrony ou systemd-timesyncd sur un "
                "serveur Linux). Le conteneur suit l'horloge de l'hôte.",
                sens, ecart, m.reference, TOLERANCE_JWT_SECONDES,
            )
        elif etat == "decale":
            logger.warning(
                "Horloge du serveur %s de %s sur %s. Au-delà de %d s, les "
                "jetons Supabase seront refusés : vérifiez la synchronisation "
                "de l'heure de la machine hôte.",
                sens, ecart, m.reference, TOLERANCE_JWT_SECONDES,
            )
        else:
            logger.info(
                "Horloge : écart de %+.1f s avec %s (tolérance des jetons : %d s).",
                m.ecart, m.reference, TOLERANCE_JWT_SECONDES,
            )

    def resume(self) -> dict:
        """État pour `GET /health/clock` (supervision)."""
        m = self.derniere
        return {
            "status": self.etat(),
            "ecart_secondes": round(m.ecart, 1) if m else None,
            "incertitude_secondes": round(m.incertitude, 1) if m else None,
            "tolerance_jwt_secondes": TOLERANCE_JWT_SECONDES,
            "seuil_alerte_secondes": self.seuil_alerte,
            "reference": m.reference if m else urlsplit(self.url).hostname,
            "mesure_le": m.mesure_le.isoformat() if m else None,
            "erreur": self.erreur,
        }

    async def _boucle(self) -> None:
        while True:
            await self.verifier()
            await asyncio.sleep(self.intervalle)

    def demarrer(self) -> None:
        """Lance les vérifications en arrière-plan (ne retarde pas le
        démarrage de l'API)."""
        if self.active and self._tache is None:
            self._tache = asyncio.create_task(self._boucle())

    async def arreter(self) -> None:
        if self._tache is not None:
            self._tache.cancel()
            try:
                await self._tache
            except asyncio.CancelledError:
                pass
            self._tache = None
        if self._client_interne:
            await self._client.aclose()


_surveillance: SurveillanceHorloge | None = None


def init_surveillance_horloge(
    url: str, *, seuil_alerte: float, intervalle: int
) -> SurveillanceHorloge:
    global _surveillance
    _surveillance = SurveillanceHorloge(
        url, seuil_alerte=seuil_alerte, intervalle=intervalle
    )
    _surveillance.demarrer()
    return _surveillance


def get_surveillance_horloge() -> SurveillanceHorloge | None:
    return _surveillance


async def close_surveillance_horloge() -> None:
    global _surveillance
    if _surveillance is not None:
        await _surveillance.arreter()
        _surveillance = None
