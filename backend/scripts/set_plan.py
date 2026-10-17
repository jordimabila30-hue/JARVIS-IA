"""Change l'abonnement d'un utilisateur et l'applique immédiatement.

Usage (depuis jarvis/backend) :
  python -m scripts.set_plan tony@stark.dev pro                  # suit l'offre Pro (plan_config)
  python -m scripts.set_plan tony@stark.dev free                 # suit l'offre Free
  python -m scripts.set_plan tony@stark.dev pro --messages 500 --tokens 1000000   # exception
  python -m scripts.set_plan tony@stark.dev pro --illimite       # exception : illimité

Sans --messages / --tokens / --illimite, le compte HÉRITE des limites de son
offre (`users.limits_override = false`). Avec, c'est une exception
individuelle (`limits_override = true`) ; une limite omise est illimitée.
Les valeurs des offres se changent dans la table `plan_config` (Supabase).

Met à jour `public.users` puis vide le cache Redis des limites.
"""

import argparse
import asyncio
import sys

from redis.asyncio import Redis

from app.config import get_settings
from app.quota import limits_cache_keys
from app.supabase_client import SupabaseAdmin


async def main() -> int:
    parser = argparse.ArgumentParser(description="Changer l'abonnement d'un utilisateur JARVIS")
    parser.add_argument("email")
    parser.add_argument("plan", choices=["free", "pro"])
    parser.add_argument("--messages", type=int, help="exception : limite de messages / jour")
    parser.add_argument("--tokens", type=int, help="exception : limite de tokens / jour")
    parser.add_argument("--illimite", action="store_true", help="exception : aucune limite quotidienne")
    args = parser.parse_args()
    exception = args.illimite or args.messages is not None or args.tokens is not None

    settings = get_settings()
    supabase = SupabaseAdmin(settings.supabase_url, settings.supabase_service_role_key)
    redis = Redis.from_url(settings.redis_url, decode_responses=True)
    try:
        user_id = await supabase.find_user_id(args.email)
        if user_id is None:
            print(f"Aucun utilisateur avec l'e-mail {args.email}", file=sys.stderr)
            return 1
        await supabase.set_user_plan(user_id, args.plan, exception=exception,
                                     daily_message_limit=args.messages, daily_token_limit=args.tokens)
        await redis.delete(*limits_cache_keys(user_id))
        effectives = await supabase.get_user_limits(user_id)
    finally:
        await supabase.aclose()
        await redis.aclose()

    def fmt(v):
        return "illimité" if v is None else v

    origine = "exception individuelle" if exception else f"offre {args.plan} (plan_config)"
    print(f"{args.email} ({user_id}) -> {args.plan}, {origine} : "
          f"messages {fmt(effectives.daily_message_limit)}, tokens {fmt(effectives.daily_token_limit)} / jour")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
