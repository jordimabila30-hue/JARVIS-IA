from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    supabase_url: str
    supabase_service_role_key: str
    supabase_jwt_secret: str | None = None
    supabase_jwt_audience: str = "authenticated"
    # Clé publique : uniquement pour la console de test (/console).
    supabase_publishable_key: str | None = None

    redis_url: str = "redis://localhost:6379/0"

    quota_limits_cache_ttl: int = 300

    openai_api_key: str
    openai_base_url: str | None = None
    openai_model: str = "gpt-4o-mini"
    chat_max_output_tokens: int = 1024
    chat_history_messages: int = 20
    chat_context_ttl: int = 3600

    # Origines autorisées pour Flutter Web (liste JSON dans le .env)
    cors_origins: list[str] = ["http://localhost:3000"]

    log_level: str = "INFO"

    # Page de test http://localhost:8000/console (désactiver en production).
    enable_console: bool = True

    # Surveillance de l'horloge (voir app/horloge.py). Référence : l'en-tête
    # Date du serveur qui émet les jetons (Supabase Auth par défaut).
    clock_reference_url: str | None = None
    clock_skew_warn_seconds: float = 5.0
    # Secondes entre deux mesures ; 0 = surveillance désactivée.
    clock_check_interval: int = 900

    @property
    def supabase_issuer(self) -> str:
        return f"{self.supabase_url.rstrip('/')}/auth/v1"

    @property
    def supabase_jwks_url(self) -> str:
        return f"{self.supabase_issuer}/.well-known/jwks.json"

    @property
    def clock_reference(self) -> str:
        return self.clock_reference_url or f"{self.supabase_issuer}/health"


@lru_cache
def get_settings() -> Settings:
    return Settings()
