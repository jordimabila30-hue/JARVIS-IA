"""Vérifie le routage par abonnement SANS appel au modèle.

Usage (depuis jarvis/backend, ou dans le conteneur) :
  python -m scripts.verifier_routage

Pour chaque offre de `plan_config` : fournisseur et modèle, et l'adaptateur
MIA correspondant peut-il être préparé (clé et modèle présents) ? Affiche
aussi ABONNEMENTS_ROUTAGE et ODO_ACTIF. Aucune clé n'est affichée, aucun
appel facturable n'est fait.
"""

import asyncio
import sys

from app.config import get_settings
from app.llm import selection
from app.llm.selection import FournisseurInconnu, FournisseurNonConfigure
from app.supabase_client import SupabaseAdmin


async def main() -> int:
    s = get_settings()
    supa = SupabaseAdmin(s.supabase_url, s.supabase_service_role_key)
    try:
        offres = await supa.list_plan_config()
    finally:
        await supa.aclose()
    print(f"ABONNEMENTS_ROUTAGE={s.abonnements_routage}  ODO_ACTIF={s.odo_actif}  "
          f"ENVIRONNEMENT={s.environnement}  LLM_PROVIDER={selection.nom_configure(s)}")
    ok = True
    for o in offres:
        try:
            llm = selection.creer(o["llm_provider"], s, o["llm_model"])
            etat = f"prêt ({type(llm).__name__})"
            await llm.fermer()
        except (FournisseurInconnu, FournisseurNonConfigure) as exc:
            etat, ok = f"NON PRÊT : {exc}", False
        print(f"  {o['plan']:<5} → {o['llm_provider']} / {o['llm_model']} : {etat}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
