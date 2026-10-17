"""MIA universel : couche commune aux fournisseurs de modèles de langage.

  base.py        contrat FournisseurLLM, événements (Texte, Fin), Usage,
                 erreurs normalisées (codes de l'événement SSE `error`)
  anthropic.py   Claude (SDK officiel `anthropic`), fournisseur principal
  groq.py        GroqCloud (SDK `openai`), tests et comparaisons
  selection.py   choix du fournisseur (LLM_PROVIDER, anthropic par défaut)

Phase 1 : la couche existe et est testée, mais les routes de production
(`api/v1/chat.py`, `api/v1/contexts.py`) utilisent encore leur propre client
GroqCloud. Le raccordement est la phase 2.
Indépendant de FastAPI, Supabase, Redis et du transport SSE.
"""

from .base import (
    AppelOutil,
    DefinitionOutil,
    ErreurFournisseur,
    ErreurLLM,
    Evenement,
    Fin,
    FournisseurLLM,
    LimiteDebit,
    RaisonArret,
    Refus,
    ReponseJSON,
    RequeteTropGrande,
    Texte,
    Usage,
)
from .selection import FournisseurInconnu, FournisseurNonConfigure, creer, fournisseur

__all__ = [
    "AppelOutil", "DefinitionOutil", "ErreurFournisseur", "ErreurLLM", "Evenement", "Fin",
    "FournisseurInconnu", "FournisseurLLM", "FournisseurNonConfigure", "LimiteDebit", "RaisonArret",
    "Refus", "ReponseJSON", "RequeteTropGrande", "Texte", "Usage", "creer", "fournisseur",
]
