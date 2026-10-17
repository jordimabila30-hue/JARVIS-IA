"""Quota GroqCloud restant (essai manuel, ~15 tokens) : en-têtes de limite.

    docker run --rm -v "$PWD:/app" -w /app --env-file .env --entrypoint python backend-api tests/quota_groq.py
"""

import asyncio
import sys

sys.path.insert(0, "/app")

from app.api.v1.chat import get_openai  # noqa: E402
from app.config import get_settings  # noqa: E402


async def main():
    settings = get_settings()
    brut = await get_openai().with_options(max_retries=0).chat.completions.with_raw_response.create(
        model=settings.openai_model, messages=[{"role": "user", "content": "ok"}], max_tokens=1)
    for cle, valeur in brut.headers.items():
        if cle.startswith("x-ratelimit") or cle == "retry-after":
            print(f"{cle}: {valeur}")
    r = brut.parse()
    print("usage:", r.usage.prompt_tokens, "+", r.usage.completion_tokens)


asyncio.run(main())
