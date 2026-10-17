-- =============================================================================
-- JARVIS — Abonnements Free & Pro, phase 1 : configuration des offres
-- =============================================================================
-- Ajoute public.plan_config : UNE ligne par abonnement (public.plan_tier),
-- modifiable directement dans l'éditeur de tables Supabase (panneau de
-- configuration de l'administrateur). Le backend la lira en phase 2 ; en
-- phase 1, rien ne la lit : aucun quota ni fournisseur IA ne change.
--
-- Aucune donnée existante touchée : ni public.users (plan, limites
-- personnalisées), ni public.quota_usage, ni les compteurs Redis.
-- Aucune clé API ici (fournisseur et modèle seulement).
--
-- Accès : tables du schéma public ouvertes par défaut à anon / authenticated
-- dans Supabase → TOUT est retiré explicitement. Lecture seule : service_role
-- (backend). Modification : administrateur (éditeur de tables / SQL du
-- tableau de bord), jamais l'application ni le backend.
--
-- Ré-exécutable (IF NOT EXISTS, ON CONFLICT DO NOTHING : une valeur modifiée
-- à la main n'est jamais écrasée). Retour arrière : drop table public.plan_config;
-- =============================================================================

create table if not exists public.plan_config (
  plan                        public.plan_tier primary key,
  llm_provider                text        not null,
  llm_model                   text        not null,
  daily_message_limit         integer     not null,
  daily_token_limit           integer     not null,
  session_duration_minutes    integer     not null,
  session_message_limit       integer     not null,
  session_token_limit         integer     not null,
  critical_threshold_percent  integer     not null default 80,
  updated_at                  timestamptz not null default now(),

  -- Noms des fournisseurs de MIA universel (backend/app/llm/selection.py).
  constraint plan_config_llm_provider_connu
    check (llm_provider in ('anthropic', 'groq')),
  constraint plan_config_llm_model_renseigne
    check (btrim(llm_model) <> '' and char_length(llm_model) <= 100),
  constraint plan_config_limites_positives
    check (daily_message_limit >= 0 and daily_token_limit >= 0
           and session_message_limit >= 0 and session_token_limit >= 0),
  constraint plan_config_session_dans_la_journee
    check (session_message_limit <= daily_message_limit
           and session_token_limit <= daily_token_limit),
  constraint plan_config_duree_session_positive
    check (session_duration_minutes > 0),
  constraint plan_config_seuil_pourcentage
    check (critical_threshold_percent between 0 and 100)
);

drop trigger if exists plan_config_set_updated_at on public.plan_config;
create trigger plan_config_set_updated_at
  before update on public.plan_config
  for each row execute function public.set_updated_at();

comment on table public.plan_config is
  'Offres JARVIS (une ligne par abonnement). Modifiable dans l''éditeur de tables ; lue par le backend (phase 2). Aucune clé API.';
comment on column public.plan_config.plan is 'Abonnement (free, pro) : une seule ligne par abonnement.';
comment on column public.plan_config.llm_provider is 'Fournisseur IA de MIA universel : anthropic ou groq.';
comment on column public.plan_config.llm_model is 'Modèle du fournisseur (ex. claude-opus-5-5, openai/gpt-oss-120b).';
comment on column public.plan_config.daily_message_limit is 'Messages IA par jour (remise à zéro à minuit UTC).';
comment on column public.plan_config.daily_token_limit is 'Tokens IA par jour (entrée + sortie, réflexion comprise).';
comment on column public.plan_config.session_duration_minutes is 'Durée d''une session, en minutes, à partir du premier appel IA (300 = 5 h). Vaut pour les NOUVELLES sessions.';
comment on column public.plan_config.session_message_limit is 'Messages IA par session (au plus la limite quotidienne).';
comment on column public.plan_config.session_token_limit is 'Tokens IA par session (au plus la limite quotidienne).';
comment on column public.plan_config.critical_threshold_percent is 'Seuil critique des jauges, en pourcentage (0 à 100).';
comment on column public.plan_config.updated_at is 'Dernière modification (automatique).';

-- Valeurs initiales (jamais réécrites si la ligne existe déjà).
insert into public.plan_config (plan, llm_provider, llm_model,
  daily_message_limit, daily_token_limit, session_duration_minutes,
  session_message_limit, session_token_limit, critical_threshold_percent)
values
  ('free', 'groq',      'openai/gpt-oss-120b', 100,  50000, 300, 25, 15000, 80),
  ('pro',  'anthropic', 'claude-opus-5-5',     200, 100000, 300, 50, 30000, 80)
on conflict (plan) do nothing;

-- -----------------------------------------------------------------------------
-- Privilèges et Row Level Security
-- -----------------------------------------------------------------------------
-- service_role (backend) : lecture SEULEMENT, même s'il a tous les droits par
-- défaut sur le schéma public (une clé backend divulguée ne change pas les
-- offres). L'éditeur de tables utilise le rôle administrateur du tableau de
-- bord, pas service_role.
revoke all on public.plan_config from public, anon, authenticated, service_role;
grant select on public.plan_config to service_role;

-- RLS sans politique : aucun accès par l'API pour anon / authenticated, même
-- si un droit était rendu par erreur. service_role et l'administrateur du
-- tableau de bord ne sont pas soumis à la RLS.
alter table public.plan_config enable row level security;
