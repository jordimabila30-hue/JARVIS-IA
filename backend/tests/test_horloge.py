"""Surveillance de l'horloge : mesure de l'écart avec l'en-tête Date de la
référence, états, journaux, route de supervision. Aucun réseau."""

import logging
import time
from email.utils import formatdate

import httpx
import pytest

from app.horloge import (
    TOLERANCE_JWT_SECONDES,
    SurveillanceHorloge,
    mesurer_ecart,
)

URL = "https://test-project.supabase.co/auth/v1/health"


def client_avec_decalage(secondes: float, statut: int = 401) -> httpx.AsyncClient:
    """Référence dont l'horloge avance de `secondes` sur la nôtre."""

    def repondre(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            statut, headers={"Date": formatdate(time.time() + secondes, usegmt=True)}
        )

    return httpx.AsyncClient(transport=httpx.MockTransport(repondre))


@pytest.mark.parametrize("decalage", [0, 7, 201, -201])
async def test_mesure_ecart(decalage):
    async with client_avec_decalage(decalage) as client:
        m = await mesurer_ecart(client, URL)
    assert abs(m.ecart - decalage) <= m.incertitude + 0.1
    assert m.reference == "test-project.supabase.co"


@pytest.mark.parametrize(
    ("decalage", "etat", "niveau"),
    [
        (0, "ok", logging.INFO),
        (7, "decale", logging.WARNING),
        (201, "critique", logging.ERROR),
        (-201, "critique", logging.ERROR),
    ],
)
async def test_etats_et_journaux(caplog, decalage, etat, niveau):
    async with client_avec_decalage(decalage) as client:
        s = SurveillanceHorloge(URL, seuil_alerte=5, client=client)
        with caplog.at_level(logging.INFO, logger="app.horloge"):
            await s.verifier()
    assert s.etat() == etat
    message = caplog.records[-1]
    assert message.levelno == niveau
    if etat == "critique":
        assert "Token" in message.getMessage()
        assert ("en retard" if decalage > 0 else "en avance") in message.getMessage()
    resume = s.resume()
    assert resume["status"] == etat
    assert resume["tolerance_jwt_secondes"] == TOLERANCE_JWT_SECONDES


async def test_reference_injoignable_non_bloquant(caplog):
    def echouer(request):
        raise httpx.ConnectError("refusée")

    async with httpx.AsyncClient(transport=httpx.MockTransport(echouer)) as client:
        s = SurveillanceHorloge(URL, client=client)
        with caplog.at_level(logging.WARNING, logger="app.horloge"):
            assert await s.verifier() is None
    assert s.etat() == "inconnu"
    assert "ConnectError" in s.resume()["erreur"]
    assert "mesure impossible" in caplog.records[-1].getMessage()


async def test_sans_entete_date():
    async with httpx.AsyncClient(
        transport=httpx.MockTransport(lambda r: httpx.Response(200))
    ) as client:
        s = SurveillanceHorloge(URL, client=client)
        await s.verifier()
    assert s.etat() == "inconnu"


async def test_desactivee():
    s = SurveillanceHorloge(URL, intervalle=0)
    s.demarrer()
    assert s.etat() == "desactivee"
    await s.arreter()


async def test_tache_de_fond_arretee_proprement():
    async with client_avec_decalage(0) as client:
        s = SurveillanceHorloge(URL, intervalle=3600, client=client)
        s.demarrer()
        for _ in range(50):
            if s.derniere is not None:
                break
            import asyncio

            await asyncio.sleep(0.01)
        assert s.etat() == "ok"
        await s.arreter()


async def test_nouvel_essai_rapide_apres_echec():
    def echouer(request):
        raise httpx.ConnectError("DNS pas encore prêt")

    async with httpx.AsyncClient(transport=httpx.MockTransport(echouer)) as client:
        s = SurveillanceHorloge(URL, intervalle=900, client=client)
        assert s.delai_suivant(await s.verifier()) == 60
    async with client_avec_decalage(0) as client:
        s = SurveillanceHorloge(URL, intervalle=900, client=client)
        assert s.delai_suivant(await s.verifier()) == 900
