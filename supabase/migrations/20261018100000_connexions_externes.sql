-- Connexions externes (ODO phase 2 : Gmail en lecture seule).
-- Additive et ré-exécutable. Aucune donnée existante modifiée.
--
-- Une connexion = un compte externe autorisé par un utilisateur JARVIS
-- (ex. un compte Google pour Gmail, qui peut différer du compte JARVIS).
-- Le jeton de rafraîchissement Google n'est JAMAIS dans cette table : il
-- est chiffré dans Supabase Vault (`vault.secrets`), référencé par
-- `secret_id`. Seules les fonctions ci-dessous (SECURITY DEFINER,
-- exécutables par le backend `service_role`) le créent, le lisent, le
-- remplacent ou le suppriment. Le client lit uniquement les colonnes non
-- sensibles de SES connexions (RLS + droits par colonne) et n'écrit rien.
--
-- Phase 2 : une connexion par fournisseur et par utilisateur
-- (unique user_id, provider). Plusieurs comptes Gmail plus tard : remplacer
-- cette contrainte par (user_id, provider, account_email).

create table if not exists public.external_connections (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null references public.users(id) on delete cascade,
  provider          text not null,
  account_email     text not null,
  scopes            text[] not null default '{}',
  status            text not null default 'active',
  secret_id         uuid,
  last_error        text,
  connected_at      timestamptz not null default now(),
  last_used_at      timestamptz,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  constraint external_connections_unique unique (user_id, provider),
  constraint external_connections_provider check (provider in ('gmail')),
  constraint external_connections_status check (status in ('active', 'a_renouveler')),
  constraint external_connections_email check (char_length(account_email) between 3 and 320),
  constraint external_connections_erreur check (last_error is null or char_length(last_error) <= 100)
);

comment on table public.external_connections is
  'Comptes externes autorisés (Gmail lecture seule). Jeton de rafraîchissement dans Vault (secret_id), jamais lisible par le client.';

drop trigger if exists external_connections_set_updated_at on public.external_connections;
create trigger external_connections_set_updated_at
  before update on public.external_connections
  for each row execute function public.set_updated_at();

-- Le secret Vault suit la ligne : supprimé avec elle (déconnexion, compte supprimé).
create or replace function public.external_connections_supprimer_secret()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.secret_id is not null then
    delete from vault.secrets where id = old.secret_id;
  end if;
  return old;
end;
$$;

drop trigger if exists external_connections_supprimer_secret on public.external_connections;
create trigger external_connections_supprimer_secret
  after delete on public.external_connections
  for each row execute function public.external_connections_supprimer_secret();

-- Droits : le client lit ses colonnes non sensibles, n'écrit jamais.
alter table public.external_connections enable row level security;

drop policy if exists external_connections_select_own on public.external_connections;
create policy external_connections_select_own on public.external_connections
  for select to authenticated using (user_id = auth.uid());

revoke all on public.external_connections from anon, authenticated;
grant select (id, user_id, provider, account_email, scopes, status, connected_at, last_used_at, updated_at)
  on public.external_connections to authenticated;
revoke all on public.external_connections from service_role;
grant select on public.external_connections to service_role;

-- Enregistre (ou remplace) la connexion d'un compte : nouveau compte Google,
-- nouveau jeton. Le jeton précédent est écrasé dans Vault (jamais conservé).
create or replace function public.enregistrer_connexion_externe(
  p_user_id uuid, p_provider text, p_email text, p_scopes text[], p_jeton text
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_secret uuid;
begin
  if p_jeton is null or char_length(p_jeton) < 10 then
    raise exception 'jeton invalide' using errcode = '22023';
  end if;
  select id, secret_id into v_id, v_secret
    from public.external_connections
   where user_id = p_user_id and provider = p_provider
   for update;
  if v_id is null then
    v_id := gen_random_uuid();
    v_secret := vault.create_secret(p_jeton, 'jarvis_connexion_' || v_id::text,
                                    'Jeton de rafraîchissement ' || p_provider || ' (JARVIS)');
    insert into public.external_connections (id, user_id, provider, account_email, scopes, status, secret_id)
    values (v_id, p_user_id, p_provider, lower(p_email), coalesce(p_scopes, '{}'), 'active', v_secret);
  else
    if v_secret is null then
      v_secret := vault.create_secret(p_jeton, 'jarvis_connexion_' || v_id::text,
                                      'Jeton de rafraîchissement ' || p_provider || ' (JARVIS)');
    else
      perform vault.update_secret(v_secret, p_jeton);
    end if;
    update public.external_connections
       set account_email = lower(p_email), scopes = coalesce(p_scopes, '{}'), status = 'active',
           secret_id = v_secret, last_error = null, connected_at = now()
     where id = v_id;
  end if;
  return v_id;
end;
$$;

-- Connexion et jeton (backend seulement), pour CE compte.
create or replace function public.jeton_connexion_externe(p_user_id uuid, p_provider text)
returns table (connexion_id uuid, account_email text, scopes text[], status text, jeton text)
language sql
stable
security definer
set search_path = ''
as $$
  select c.id, c.account_email, c.scopes, c.status, s.decrypted_secret
    from public.external_connections c
    left join vault.decrypted_secrets s on s.id = c.secret_id
   where c.user_id = p_user_id and c.provider = p_provider;
$$;

-- État (actif, à renouveler) et dernière erreur (code court, jamais un jeton).
create or replace function public.marquer_connexion_externe(
  p_user_id uuid, p_provider text, p_status text, p_erreur text default null
) returns void
language sql
security definer
set search_path = ''
as $$
  update public.external_connections
     set status = p_status, last_error = left(p_erreur, 100),
         last_used_at = case when p_status = 'active' then now() else last_used_at end
   where user_id = p_user_id and provider = p_provider;
$$;

-- Déconnexion : la ligne et son secret Vault disparaissent (déclencheur).
create or replace function public.supprimer_connexion_externe(p_user_id uuid, p_provider text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.external_connections where user_id = p_user_id and provider = p_provider;
  return found;
end;
$$;

revoke all on function public.enregistrer_connexion_externe(uuid, text, text, text[], text) from public, anon, authenticated;
revoke all on function public.jeton_connexion_externe(uuid, text) from public, anon, authenticated;
revoke all on function public.marquer_connexion_externe(uuid, text, text, text) from public, anon, authenticated;
revoke all on function public.supprimer_connexion_externe(uuid, text) from public, anon, authenticated;
revoke all on function public.external_connections_supprimer_secret() from public, anon, authenticated;
grant execute on function public.enregistrer_connexion_externe(uuid, text, text, text[], text) to service_role;
grant execute on function public.jeton_connexion_externe(uuid, text) to service_role;
grant execute on function public.marquer_connexion_externe(uuid, text, text, text) to service_role;
grant execute on function public.supprimer_connexion_externe(uuid, text) to service_role;
