-- Supprimer une ligne de public.users supprime aussi le compte Supabase Auth.
--
-- Avant : supprimer le profil (tableau de bord, service_role) laissait le
-- compte dans auth.users (connexion possible, profil introuvable, adresse
-- e-mail « déjà utilisée »). Désormais les deux disparaissent ensemble.
--
-- Sens inverse inchangé : supprimer le compte dans Authentication supprime
-- déjà le profil (clé étrangère public.users.id → auth.users ON DELETE
-- CASCADE) ; le déclencheur ne trouve alors plus de compte et ne fait rien.
--
-- Qui peut déclencher ? Seuls postgres et service_role ont le droit DELETE
-- sur public.users (aucune politique RLS DELETE pour authenticated) : un
-- utilisateur de l'application ne peut pas supprimer de compte par ce biais.
-- TRUNCATE ne déclenche pas les déclencheurs par ligne : il ne supprime
-- aucun compte.

create or replace function public.supprimer_compte_du_profil()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Les données liées (conversations, contextes, quotas, connexions…)
  -- partent par les clés étrangères ON DELETE CASCADE existantes.
  delete from auth.users where id = old.id;
  return old;
end;
$$;

revoke all on function public.supprimer_compte_du_profil() from public, anon, authenticated;

drop trigger if exists users_supprimer_compte on public.users;
create trigger users_supprimer_compte
  after delete on public.users
  for each row execute function public.supprimer_compte_du_profil();
