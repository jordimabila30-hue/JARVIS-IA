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

    # Cache des limites effectives (plan_config + abonnement) : délai maximal
    # avant qu'une modification faite dans Supabase s'applique.
    quota_limits_cache_ttl: int = 30

    # MIA universel (app/llm/) : fournisseur de toutes les demandes ordinaires.
    llm_provider: str = "anthropic"
    anthropic_api_key: str | None = None
    anthropic_model: str | None = None     # aucun modèle imposé par le code
    anthropic_effort: str | None = None    # low | medium | high | xhigh | max
    # Claude n'a pas la limite de 8 000 tokens/min du compte GroqCloud : plus
    # d'extraits WhatsApp par question (budget d'entrée estimé).
    anthropic_comprehension_budget_tokens: int = 20000
    # Réflexion interne comptée dans le plafond de sortie (Claude) : marge
    # ajoutée aux plafonds habituels, pour ne pas couper la réponse visible.
    llm_reflexion_marge_tokens: int = 8000
    # Effort des lots de propositions (JSON) : court, comme avant (gpt-oss).
    llm_effort_propositions: str | None = "low"

    # Choix manuel du fournisseur (en-tête X-Jarvis-Fournisseur) : tests et
    # comparaisons seulement. Refusé en production et hors de LLM_ADMINS
    # (identifiants Supabase des comptes autorisés).
    environnement: str = "production"
    # Abonnements, phase 2 : true = fournisseur et modèle de l'offre du compte
    # (plan_config : Free → groq, Pro → anthropic) ; false = LLM_PROVIDER pour
    # tous (comportement actuel). Activation contrôlée, retour arrière = false.
    abonnements_routage: bool = False
    llm_selection_manuelle: bool = False
    llm_admins: list[str] = []

    # ODO (outils), indépendant de ABONNEMENTS_ROUTAGE. false = chat inchangé :
    # aucun outil proposé, aucun appel supplémentaire. Outils fictifs : tests
    # hors production seulement. Les limites ci-dessous sont des garde-fous
    # techniques par demande, jamais des quotas utilisateur.
    odo_actif: bool = False
    odo_outils_fictifs: bool = False
    odo_max_tours: int = 4                     # tours du modèle par demande
    odo_max_appels: int = 8                    # appels d'outils par demande
    odo_delai_outil: float = 10.0              # secondes par exécution
    odo_resultat_max_caracteres: int = 6000    # résultat renvoyé au modèle
    odo_confirmation_ttl: int = 300            # validité d'une action à confirmer (s)

    # GroqCloud (ou OpenAI) : fournisseur « groq », réservé aux tests.
    openai_api_key: str = ""
    openai_base_url: str | None = None
    openai_model: str = "gpt-4o-mini"
    chat_max_output_tokens: int = 1024
    chat_history_messages: int = 20
    chat_context_ttl: int = 3600

    # Origines autorisées pour Flutter Web (liste JSON dans le .env)
    cors_origins: list[str] = ["http://localhost:3000"]

    log_level: str = "INFO"

    # Contextes WhatsApp joints (voir app/contextes.py).
    whatsapp_context_max_messages: int = 5000
    whatsapp_context_max_chars: int = 2_000_000   # texte total des messages
    whatsapp_context_max_bytes: int = 8_000_000   # corps de la requête
    whatsapp_context_page_max: int = 500          # messages par page
    whatsapp_context_timeout: float = 30.0        # enregistrement (secondes)

    # Moteur de compréhension conversationnelle (app/comprehension/).
    # Budget de la requête envoyée au modèle (tokens estimés) : le compte
    # GroqCloud actuel limite à 8 000 tokens PAR MINUTE (en-tête
    # x-ratelimit-limit-tokens), bien en dessous de la fenêtre du modèle
    # (131 072). À relever si la limite du compte augmente.
    comprehension_budget_tokens: int = 6000
    comprehension_history_tokens: int = 1200      # historique du chat, dans ce budget
    comprehension_max_output_tokens: int = 1500   # raisonnement du modèle compris
    # Aide à répondre probable : part du budget d'entrée de la réponse
    # principale laissée aux LOTS de propositions qui la suivent dans la
    # même minute (correction finale 5.1, app/comprehension/generation.py).
    comprehension_extra_output_tokens: int = 2500
    # Génération des propositions par lots : tons par requête, requêtes au
    # plus par génération (reprises comprises), sortie maximale d'un lot,
    # attente maximale cumulée sur les 429 (limite par minute) avant de
    # s'arrêter en « Génération incomplète ».
    propositions_tons_par_lot: int = 2
    propositions_max_requetes: int = 5
    propositions_lot_max_tokens: int = 2600
    propositions_attente_max: float = 45.0
    comprehension_cache_ttl: int = 3600           # messages des pièces jointes (Redis)

    # Limite de débit du fournisseur (429) : attente maximale avant d'abandonner,
    # pendant laquelle le flux reste ouvert (commentaires SSE).
    llm_rate_limit_max_wait: float = 25.0

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
