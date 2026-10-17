"""Quota GroqCloud restant (essai manuel, ~15 tokens) : en-têtes de limite.

    docker run --rm -v "$PWD:/app" -w /app --env-file .env --entrypoint python backend-api tests/quota_groq.py
"""

import asyncio
import sys

sys.path.insert(0, "/app")

from openai import AsyncOpenAI  # noqa: E402

from app.config import get_settings  # noqa: E402
from app.llm.groq import adresse  # noqa: E402


async def main():
    settings = get_settings()
    # En-têtes bruts propres à GroqCloud : client direct (même adresse que MIA).
    client = AsyncOpenAI(api_key=settings.openai_api_key, max_retries=0,
                         base_url=adresse(settings.openai_api_key, settings.openai_base_url))
    brut = await client.chat.completions.with_raw_response.create(
        model=settings.openai_model, messages=[{"role": "user", "content": "ok"}], max_tokens=1)
    for cle, valeur in brut.headers.items():
        if cle.startswith("x-ratelimit") or cle == "retry-after":
            print(f"{cle}: {valeur}")
    r = brut.parse()
    print("usage:", r.usage.prompt_tokens, "+", r.usage.completion_tokens)


asyncio.run(main())
