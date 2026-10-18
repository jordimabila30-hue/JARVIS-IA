-- Abonnements : quotas QUOTIDIENS seulement, et users ↔ plan_config synchronisés.
-- Additive et ré-exécutable. Aucune consommation touchée (quota_usage,
-- usage_sessions, llm_usage inchangées).
--
-- 1. Plus de quota de session : les colonnes de session de plan_config
--    deviennent facultatives et sont vidées. Le backend (quota.py) ne crée
--    aucune session quand `session_duration_minutes` est NULL ; remettre une
--    durée réactiverait le mécanisme, conservé tel quel.
-- 2. users.daily_message_limit / daily_token_limit reflètent toujours les
--    limites EFFECTIVES : celles de l'offre (plan_config), sauf exception
--    explicite (limits_override = true, valeurs personnelles gardées).
--    Recopiées quand l'offre change, quand users.plan change, quand
--    l'exception est retirée, et à la création d'un compte.
--    limites_effectives() reste le seul calcul utilisé par le backend.

-- 1. Sessions ---------------------------------------------------------------
alter table public.plan_config alter column session_duration_minutes drop not null;
alter table public.plan_config alter column session_message_limit    drop not null;
alter table public.plan_config alter column session_token_limit      drop not null;

update public.plan_config
   set session_duration_minutes = null, session_message_limit = null, session_token_limit = null
 where session_duration_minutes is not null
    or session_message_limit is not null
    or session_token_limit is not null;

-- 2. users suit son offre ---------------------------------------------------
-- Compte (création, changement d'offre, exception retirée…) : limites de
-- l'offre recopiées, sauf exception. SECURITY DEFINER : plan_config n'est
-- pas lisible par le client, dont les mises à jour (display_name…)
-- déclenchent aussi cette fonction.
create or replace function public.users_suivre_offre()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not new.limits_override then
    select c.daily_message_limit, c.daily_token_limit
      into new.daily_message_limit, new.daily_token_limit
      from public.plan_config c
     where c.plan = new.plan;
  end if;
  return new;
end;
$$;

revoke all on function public.users_suivre_offre() from public, anon, authenticated;

drop trigger if exists users_suivre_offre on public.users;
create trigger users_suivre_offre
  before insert or update on public.users
  for each row execute function public.users_suivre_offre();

-- Offre modifiée : tous ses comptes sans exception suivent.
create or replace function public.plan_config_propager()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.users u
     set daily_message_limit = new.daily_message_limit,
         daily_token_limit   = new.daily_token_limit
   where u.plan = new.plan
     and not u.limits_override
     and (u.daily_message_limit is distinct from new.daily_message_limit
          or u.daily_token_limit is distinct from new.daily_token_limit);
  return null;
end;
$$;

revoke all on function public.plan_config_propager() from public, anon, authenticated;

drop trigger if exists plan_config_propager on public.plan_config;
create trigger plan_config_propager
  after insert or update of daily_message_limit, daily_token_limit on public.plan_config
  for each row execute function public.plan_config_propager();

-- Comptes existants : alignés une fois (exceptions intactes).
update public.users u
   set daily_message_limit = c.daily_message_limit,
       daily_token_limit   = c.daily_token_limit
  from public.plan_config c
 where c.plan = u.plan
   and not u.limits_override
   and (u.daily_message_limit is distinct from c.daily_message_limit
        or u.daily_token_limit is distinct from c.daily_token_limit);

comment on column public.users.daily_message_limit is
  'Limite quotidienne de messages EFFECTIVE : copie de plan_config (trigger), sauf exception (limits_override).';
comment on column public.users.daily_token_limit is
  'Limite quotidienne de tokens EFFECTIVE : copie de plan_config (trigger), sauf exception (limits_override).';
