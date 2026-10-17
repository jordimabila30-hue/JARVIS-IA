"""Budget d'une campagne d'essais réels de MIA universel (lecture seule).

Additionne les tokens que JARVIS a enregistrés (`messages.tokens_input` /
`tokens_output`) pour les réponses de Claude depuis le début de la campagne,
et estime le coût. Majorant : l'entrée est comptée au tarif plein, même la
part servie par le cache. La réflexion interne est déjà dans la sortie.

  docker exec jarvis-api-mia python /repo/backend/scripts/budget_mia.py --depuis 2026-10-17T11:56:00Z

N'appelle jamais l'API Claude ; ne lit ni n'affiche aucune clé.
"""

import argparse
import asyncio
import sys

sys.path.insert(0, "/app")

from app.config import get_settings  # noqa: E402
from app.supabase_client import SupabaseAdmin  # noqa: E402


async def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--depuis", required=True, help="début de la campagne (ISO 8601, UTC)")
    p.add_argument("--budget", type=float, default=0.20, help="limite en USD")
    p.add_argument("--entree", type=float, default=4.0, help="USD par million de tokens d'entrée")
    p.add_argument("--sortie", type=float, default=20.0, help="USD par million de tokens de sortie")
    p.add_argument("--pire-appel", type=float, default=0.022,
                   help="coût maximal d'un appel avec les plafonds de l'instance de test")
    args = p.parse_args()
    s = get_settings()
    supa = SupabaseAdmin(s.supabase_url, s.supabase_service_role_key)
    try:
        r = await supa._http.get("/messages", params={
            "role": "eq.assistant", "model": "like.claude*", "created_at": f"gte.{args.depuis}",
            "select": "created_at,model,tokens_input,tokens_output", "order": "created_at.asc"})
        r.raise_for_status()
        lignes = r.json()
    finally:
        await supa.aclose()
    total = 0.0
    for l in lignes:
        entree, sortie = l["tokens_input"] or 0, l["tokens_output"] or 0
        cout = entree * args.entree / 1e6 + sortie * args.sortie / 1e6
        total += cout
        print(f"{l['created_at'][:19]}  {l['model']}  {entree:6d} + {sortie:5d} tokens  {cout:.4f} $  (cumul {total:.4f} $)")
    reste = args.budget - total
    print(f"\n{len(lignes)} réponse(s) de Claude, coût estimé {total:.4f} $ / budget {args.budget:.2f} $ ; reste {reste:.4f} $")
    if reste < args.pire_appel:
        print("ARRÊT : la prochaine requête risquerait de dépasser le budget.")
        return 1
    print(f"Prochaine requête possible (pire cas {args.pire_appel:.3f} $).")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
