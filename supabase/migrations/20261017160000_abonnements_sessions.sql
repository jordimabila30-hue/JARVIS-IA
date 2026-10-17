-- =============================================================================
-- JARVIS — Abonnements Free & Pro, phase 2 : limites effectives, exceptions,
-- sessions, suivi par fournisseur
-- =============================================================================
-- Règle : public.plan_config définit les limites de chaque abonnement ;
-- public.users dit à quel abonnement appartient chaque compte. Une limite
-- personnelle ne s'applique QUE si l'exception est activée explicitement
-- (users.limits_override = true). Les anciennes colonnes
-- users.daily_message_limit / daily_token_limit ne sont lues que dans ce cas
-- (NULL y garde son sens : illimité) ; sinon elles sont ignorées.
--
-- Additive et ré-exécutable : aucune donnée existante transformée. Tous les
-- comptes ont limits_override = false (valeur par défaut) : ils suivent leur
-- offre, y compris le compte Pro qui avait 60 / 100 000 (transition voulue).
--
-- Sessions : fenêtre de temps persistante, ouverte au premier appel IA
-- autorisé, durée lue dans plan_config à l'ouverture (ends_at figé : une
-- modification vaut pour les NOUVELLES sessions). Heure du serveur seulement.
-- Écriture par le backend (fonctions SECURITY DEFINER réservées au
-- service_role) ; lecture de SES sessions pour l'utilisateur.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Exception explicite sur public.users
-- -----------------------------------------------------------------------------
alter table public.users
  add column if not exists limits_override boolean not null default false;

comment on column public.users.limits_override is
  'Exception individuelle : true = daily_message_limit / daily_token_limit de ce compte s''appliquent (NULL = illimité) ; false = limites de l''offre (plan_config).';
comment on column public.users.daily_message_limit is
  'Limite personnelle de messages / jour, lue SEULEMENT si limits_override = true (NULL = illimité).';
comment on column public.users.daily_token_limit is
  'Limite personnelle de tokens / jour, lue SEULEMENT si limits_override = true (NULL = illimité).';
-- Droits : l'utilisateur ne peut mettre à jour que display_name, avatar_url,
-- preferences (droit par colonne existant) : limits_override n'en fait pas partie.

-- -----------------------------------------------------------------------------
-- 2. Limites effectives (seule source du calcul : backend, get_my_quota, vue)
-- -----------------------------------------------------------------------------
create or replace function public.limites_effectives(p_user_id uuid)
returns table (
  plan                       public.plan_tier,
  limits_override            boolean,
  llm_provider               text,
  llm_model                  text,
  daily_message_limit        integer,
  daily_token_limit          integer,
  session_duration_minutes   integer,
  session_message_limit      integer,
  session_token_limit        integer,
  critical_threshold_percent integer
)
language sql
stable
security definer
set search_path = ''
as $$
  select u.plan,
         u.limits_override,
         c.llm_provider,
         c.llm_model,
         case when u.limits_override then u.daily_message_limit else c.daily_message_limit end,
         case when u.limits_override then u.daily_token_limit   else c.daily_token_limit   end,
         c.session_duration_minutes,
         c.session_message_limit,
         c.session_token_limit,
         c.critical_threshold_percent
    from public.users u
    join public.plan_config c on c.plan = u.plan
   where u.id = p_user_id;
$$;

revoke all on function public.limites_effectives(uuid) from public, anon, authenticated;
grant execute on function public.limites_effectives(uuid) to service_role;

-- get_my_quota (lecture du quota du jour par l'utilisateur) : limites
-- EFFECTIVES, plus jamais les anciennes colonnes seules. Même signature.
create or replace function public.get_my_quota()
returns table (
  plan                public.plan_tier,
  daily_message_limit integer,
  daily_token_limit   integer,
  messages_used       integer,
  tokens_used         integer,
  usage_date          date
)
language sql
stable
security definer
set search_path = ''
as $$
  select l.plan,
         l.daily_message_limit,
         l.daily_token_limit,
         coalesce(q.messages_used, 0),
         coalesce(q.tokens_used, 0),
         (now() at time zone 'utc')::date
    from public.limites_effectives(auth.uid()) l
    left join public.quota_usage q
      on q.user_id = auth.uid()
     and q.usage_date = (now() at time zone 'utc')::date;
$$;

revoke all on function public.get_my_quota() from public, anon;
grant execute on function public.get_my_quota() to authenticated;

-- -----------------------------------------------------------------------------
-- 3. Sessions d'utilisation
-- -----------------------------------------------------------------------------
create table if not exists public.usage_sessions (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references public.users (id) on delete cascade,
  plan           public.plan_tier not null,
  started_at     timestamptz not null default now(),
  ends_at        timestamptz not null,
  messages_used  integer not null default 0 check (messages_used >= 0),
  tokens_used    integer not null default 0 check (tokens_used >= 0),
  updated_at     timestamptz not null default now(),
  constraint usage_sessions_fenetre check (ends_at > started_at)
);

create index if not exists usage_sessions_user_ends_idx
  on public.usage_sessions (user_id, ends_at desc);

comment on table public.usage_sessions is
  'Sessions d''utilisation de l''IA (fenêtre ouverte au premier appel autorisé, durée de plan_config à l''ouverture). Écrite par le backend.';

drop trigger if exists usage_sessions_set_updated_at on public.usage_sessions;
create trigger usage_sessions_set_updated_at
  before update on public.usage_sessions
  for each row execute function public.set_updated_at();

-- Session active d'un compte (lecture seule, aucune création).
create or replace function public.session_active(p_user_id uuid)
returns setof public.usage_sessions
language sql
stable
security definer
set search_path = ''
as $$
  select * from public.usage_sessions
   where user_id = p_user_id and ends_at > now()
   order by started_at desc
   limit 1;
$$;

-- Session active, ou nouvelle session si aucune n'est en cours. Verrou par
-- compte : deux premiers appels simultanés obtiennent LA même session.
create or replace function public.ouvrir_session(p_user_id uuid, p_plan public.plan_tier, p_duree_minutes integer)
returns public.usage_sessions
language plpgsql
security definer
set search_path = ''
as $$
declare
  s public.usage_sessions;
begin
  if p_duree_minutes is null or p_duree_minutes <= 0 then
    raise exception 'Durée de session invalide : %', p_duree_minutes using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('usage_sessions:' || p_user_id::text, 0));
  select * into s from public.usage_sessions
   where user_id = p_user_id and ends_at > now()
   order by started_at desc
   limit 1;
  if found then
    return s;
  end if;
  insert into public.usage_sessions (user_id, plan, started_at, ends_at)
  values (p_user_id, p_plan, now(), now() + make_interval(mins => p_duree_minutes))
  returning * into s;
  return s;
end;
$$;

-- Consommation d'un échange terminé, dans LA session où il a commencé.
create or replace function public.increment_session_usage(
  p_session_id uuid, p_user_id uuid, p_messages integer, p_tokens integer)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.usage_sessions
     set messages_used = messages_used + greatest(p_messages, 0),
         tokens_used   = tokens_used   + greatest(p_tokens, 0)
   where id = p_session_id and user_id = p_user_id;
$$;

revoke all on function public.session_active(uuid) from public, anon, authenticated;
revoke all on function public.ouvrir_session(uuid, public.plan_tier, integer) from public, anon, authenticated;
revoke all on function public.increment_session_usage(uuid, uuid, integer, integer) from public, anon, authenticated;
grant execute on function public.session_active(uuid) to service_role;
grant execute on function public.ouvrir_session(uuid, public.plan_tier, integer) to service_role;
grant execute on function public.increment_session_usage(uuid, uuid, integer, integer) to service_role;

revoke all on public.usage_sessions from public, anon, authenticated, service_role;
grant select on public.usage_sessions to authenticated, service_role;
alter table public.usage_sessions enable row level security;
drop policy if exists "usage_sessions_select_own" on public.usage_sessions;
create policy "usage_sessions_select_own" on public.usage_sessions
  for select to authenticated
  using (user_id = (select auth.uid()));

-- -----------------------------------------------------------------------------
-- 4. Suivi de la consommation par fournisseur et modèle (coûts estimés)
-- -----------------------------------------------------------------------------
-- Tokens d'entrée / sortie par jour, compte, fournisseur et modèle. Aucun
-- tarif stocké : coût estimé = tokens × prix du fournisseur (doc).
create table if not exists public.llm_usage (
  user_id        uuid   not null references public.users (id) on delete cascade,
  usage_date     date   not null default ((now() at time zone 'utc')::date),
  llm_provider   text   not null,
  llm_model      text   not null,
  requests       integer not null default 0 check (requests >= 0),
  tokens_input   bigint  not null default 0 check (tokens_input >= 0),
  tokens_output  bigint  not null default 0 check (tokens_output >= 0),
  updated_at     timestamptz not null default now(),
  primary key (user_id, usage_date, llm_provider, llm_model)
);

comment on table public.llm_usage is
  'Consommation des modèles par jour, compte, fournisseur et modèle (suivi des coûts estimés). Écrite par le backend.';

create or replace function public.increment_llm_usage(
  p_user_id uuid, p_provider text, p_model text, p_requests integer, p_input integer, p_output integer)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.llm_usage as l (user_id, usage_date, llm_provider, llm_model, requests, tokens_input, tokens_output)
  values (p_user_id, (now() at time zone 'utc')::date, p_provider, left(p_model, 100),
          greatest(p_requests, 0), greatest(p_input, 0), greatest(p_output, 0))
  on conflict (user_id, usage_date, llm_provider, llm_model) do update
     set requests      = l.requests      + excluded.requests,
         tokens_input  = l.tokens_input  + excluded.tokens_input,
         tokens_output = l.tokens_output + excluded.tokens_output,
         updated_at    = now();
$$;

revoke all on function public.increment_llm_usage(uuid, text, text, integer, integer, integer)
  from public, anon, authenticated;
grant execute on function public.increment_llm_usage(uuid, text, text, integer, integer, integer) to service_role;

revoke all on public.llm_usage from public, anon, authenticated, service_role;
grant select on public.llm_usage to service_role;
alter table public.llm_usage enable row level security;

-- -----------------------------------------------------------------------------
-- 5. Consultation par l'administrateur (schéma admin, hors API)
-- -----------------------------------------------------------------------------
create schema if not exists admin;

-- Limites RÉELLEMENT appliquées à chaque compte (sans confusion avec les
-- anciennes colonnes, ignorées sauf exception).
create or replace view admin.limites_appliquees with (security_invoker = true) as
select u.id as user_id, u.email, u.plan, u.limits_override as exception,
       l.llm_provider, l.llm_model,
       l.daily_message_limit, l.daily_token_limit,
       l.session_duration_minutes, l.session_message_limit, l.session_token_limit,
       l.critical_threshold_percent
  from public.users u
  cross join lateral public.limites_effectives(u.id) l;

create or replace view admin.consommation_llm with (security_invoker = true) as
select usage_date, llm_provider, llm_model,
       sum(requests) as requests, sum(tokens_input) as tokens_input, sum(tokens_output) as tokens_output
  from public.llm_usage
 group by usage_date, llm_provider, llm_model;

revoke all on admin.limites_appliquees, admin.consommation_llm
  from public, anon, authenticated, service_role;
