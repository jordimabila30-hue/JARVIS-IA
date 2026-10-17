"""Console de test : mini-interface de chat servie par l'API (remplace Flutter
pour les essais). Désactivable avec ENABLE_CONSOLE=false.

Elle ne contient aucun secret : la connexion se fait avec la clé publique
Supabase, puis la console appelle l'API comme le ferait l'app Flutter.
"""

from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import FileResponse

from .config import Settings, get_settings
from .llm import selection

_PAGE = Path(__file__).parent / "static" / "console.html"

router = APIRouter(prefix="/console", include_in_schema=False)


def _require_enabled(settings: Settings = Depends(get_settings)) -> Settings:
    if not settings.enable_console:
        raise HTTPException(404)
    return settings


@router.get("")
async def console_page(_: Settings = Depends(_require_enabled)) -> FileResponse:
    return FileResponse(_PAGE, headers={"Cache-Control": "no-store"})


@router.get("/config")
async def console_config(settings: Settings = Depends(_require_enabled)) -> dict:
    # MIA universel : fournisseur actif et modèles configurés (jamais une clé).
    nom = selection.nom_configure(settings)
    etat = selection.configures(settings)
    modeles = {"anthropic": settings.anthropic_model, "groq": settings.openai_model}
    return {
        "supabase_url": settings.supabase_url.rstrip("/"),
        "publishable_key": settings.supabase_publishable_key,
        "fournisseur": nom,
        "modele": modeles.get(nom),
        "configure": etat.get(nom, False),
        "fournisseurs": etat,
        # Indication pour l'affichage ; le serveur revérifie le compte (LLM_ADMINS).
        "selection_manuelle": selection.choix_manuel_possible(settings),
    }
