-- Simulation minimale de Supabase pour tester le schéma dans un PostgreSQL
-- local jetable (JAMAIS sur la base distante) : rôles, auth.uid() lu dans
-- les « claims » de la requête comme PostgREST, droits par défaut.
create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;
create role postgres_admin_stub nologin;

create schema auth;
create table auth.users (
  id uuid primary key,
  email text,
  raw_user_meta_data jsonb default '{}'::jsonb
);
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;
grant usage on schema auth to anon, authenticated, service_role;
grant execute on function auth.uid() to anon, authenticated, service_role;

-- Droits par défaut de Supabase sur le schéma public.
grant usage on schema public to anon, authenticated, service_role;
alter default privileges in schema public
  grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public
  grant all on functions to anon, authenticated, service_role;

-- Supabase Vault (simulation minimale : mêmes noms, sans chiffrement réel).
-- Comme sur Supabase, ni anon ni authenticated n'y ont accès.
create schema vault;
create table vault.secrets (
  id uuid primary key default gen_random_uuid(),
  name text unique,
  description text not null default '',
  secret text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create function vault.create_secret(new_secret text, new_name text default null,
                                    new_description text default '', new_key_id uuid default null)
returns uuid language sql as $$
  insert into vault.secrets (secret, name, description) values (new_secret, new_name, new_description)
  returning id
$$;
create function vault.update_secret(secret_id uuid, new_secret text default null, new_name text default null,
                                    new_description text default null, new_key_id uuid default null)
returns void language sql as $$
  update vault.secrets set secret = coalesce(new_secret, secret), updated_at = now() where id = secret_id
$$;
create view vault.decrypted_secrets as
  select id, name, description, secret, secret as decrypted_secret, created_at, updated_at from vault.secrets;
revoke all on schema vault from public, anon, authenticated;
