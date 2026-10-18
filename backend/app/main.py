import logging
from contextlib import asynccontextmanager

import httpx
from fastapi import Depends, FastAPI, Response, status
from fastapi.middleware.cors import CORSMiddleware
from redis.exceptions import RedisError

from . import console
from .api.v1 import chat, contexts, integrations, local_exchanges, odo
from .llm import FournisseurNonConfigure, selection
from .auth import AuthUser, get_current_user
from .config import Settings, get_settings
from .integrations.google import close_google, init_google
from .horloge import (
    close_surveillance_horloge,
    get_surveillance_horloge,
    init_surveillance_horloge,
)
from .quota import QuotaService, get_quota_service, init_quota_service
from .redis_client import close_redis, get_redis, init_redis
from .supabase_client import close_supabase, get_supabase, init_supabase

logging.basicConfig(
    level=get_settings().log_level,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings = get_settings()
    redis = await init_redis(settings.redis_url)
    supabase = init_supabase(settings.supabase_url, settings.supabase_service_role_key)
    init_quota_service(redis, supabase, limits_cache_ttl=settings.quota_limits_cache_ttl)
    google = init_google(settings, redis, supabase)
    # Mesures en arrière-plan : ne retarde pas le démarrage.
    init_surveillance_horloge(
        settings.clock_reference,
        seuil_alerte=settings.clock_skew_warn_seconds,
        intervalle=settings.clock_check_interval,
    )
    # MIA universel : fournisseur actif annoncé (nom et modèle, jamais une clé).
    actif = selection.nom_configure(settings)
    if selection.configures(settings).get(actif):
        logger.info("Fournisseur IA : %s", actif)
    else:
        logger.error("Fournisseur IA « %s » non configuré : le chat répondra 503 (llm_config).", actif)
    logger.info("Routage par abonnement : %s", "ACTIF (offre du compte, plan_config)"
                if settings.abonnements_routage else f"inactif ({actif} pour tous)")
    if settings.abonnements_routage:
        # Chaque offre peut viser un autre fournisseur : tous doivent être
        # prêts (sinon les comptes concernés recevront 503 llm_config).
        manquants = [nom for nom, ok in selection.configures(settings).items() if not ok]
        if manquants:
            logger.error("Routage actif mais fournisseur(s) non configuré(s) : %s", ", ".join(manquants))
    logger.info("ODO : %s", "ACTIF" if settings.odo_actif else "inactif (aucun outil proposé)")
    logger.info("Gmail : %s", "configuré (lecture seule)" if google.configure else "non configuré")
    yield
    await close_surveillance_horloge()
    # Laisse les sauvegardes de fin de flux se terminer avant de fermer les clients.
    await chat.wait_background_tasks()
    await selection.fermer_tous()
    await close_google()
    await close_supabase()
    await close_redis()


app = FastAPI(title="JARVIS API", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=get_settings().cors_origins,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE"],   # PUT : phase 4 ; PATCH : phase 5
    allow_headers=["Authorization", "Content-Type"],
    # Sans ça, Flutter Web ne peut pas lire les en-têtes de quota.
    expose_headers=[
        "X-Quota-Plan",
        "X-Quota-Messages-Limit",
        "X-Quota-Messages-Remaining",
        "X-Quota-Tokens-Limit",
        "X-Quota-Tokens-Remaining",
        "X-Quota-Reset",
        "X-Quota-Session-Messages-Remaining",
        "X-Quota-Session-Tokens-Remaining",
        "X-Quota-Session-Reset",
        "Retry-After",
    ],
)

app.include_router(chat.router, prefix="/api/v1")
app.include_router(local_exchanges.router, prefix="/api/v1")
app.include_router(contexts.conversations_router, prefix="/api/v1")
app.include_router(contexts.contexts_router, prefix="/api/v1")
app.include_router(odo.router, prefix="/api/v1")
app.include_router(integrations.router, prefix="/api/v1")
app.include_router(console.router)


@app.get("/health")
async def health() -> dict:
    """Vivacité : le processus répond."""
    return {"status": "ok"}


@app.get("/health/ready")
async def ready(response: Response) -> dict:
    """Disponibilité : Redis et Supabase joignables."""
    checks = {}
    try:
        await get_redis().ping()
        checks["redis"] = "ok"
    except RedisError as exc:
        checks["redis"] = f"erreur : {exc}"
    try:
        await get_supabase().ping()
        checks["supabase"] = "ok"
    except httpx.HTTPError as exc:
        checks["supabase"] = f"erreur : {exc}"

    ok = all(v == "ok" for v in checks.values())
    if not ok:
        response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE
    return {"status": "ok" if ok else "degraded", **checks}


@app.get("/health/clock")
async def clock(response: Response) -> dict:
    """Écart d'horloge avec le serveur des jetons (supervision). 503 si
    l'écart dépasse la tolérance des JWT : les jetons sont alors refusés."""
    surveillance = get_surveillance_horloge()
    if surveillance is None:
        return {"status": "desactivee"}
    etat = surveillance.resume()
    if etat["status"] == "critique":
        response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE
    return etat


@app.get("/me")
async def me(user: AuthUser = Depends(get_current_user)) -> dict:
    return {"id": user.id, "email": user.email}


@app.get("/me/quota")
async def my_quota(
    response: Response,
    user: AuthUser = Depends(get_current_user),
    service: QuotaService = Depends(get_quota_service),
    settings: Settings = Depends(get_settings),
) -> dict:
    """Utilisation du compte (jauges de l'app) : abonnement, offre (fournisseur,
    modèle, seuil critique), jour (utilisé / autorisé, réinitialisation à
    minuit UTC), session (utilisée / autorisée, durée, fin) et fournisseur
    réellement utilisé. Lecture seule : n'ouvre aucune session."""
    quota = await service.get_status(user.id)
    response.headers.update(quota.headers())
    donnees = quota.to_dict()
    try:
        nom, modele = chat.fournisseur_attendu(await service.get_limits(user.id), settings)
    except FournisseurNonConfigure:
        nom = modele = None
    donnees["fournisseur_actif"] = {
        "llm_provider": nom, "llm_model": modele, "routage_abonnement": settings.abonnements_routage,
    }
    return donnees
