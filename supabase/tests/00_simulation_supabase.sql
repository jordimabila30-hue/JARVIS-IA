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
