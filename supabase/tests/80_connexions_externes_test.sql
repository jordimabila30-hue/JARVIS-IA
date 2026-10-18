-- Connexions externes (Gmail) : jetons dans Vault, isolation, droits (après 70_*).
\set ON_ERROR_STOP on
reset role;

insert into auth.users (id, email) values
  ('cccccccc-0000-0000-0000-00000000000a', 'cx-a@test.local'),
  ('cccccccc-0000-0000-0000-00000000000b', 'cx-b@test.local');

-- Backend (service_role) : enregistrement, jeton dans Vault seulement
set role service_role;
select tests.ok((select public.enregistrer_connexion_externe('cccccccc-0000-0000-0000-00000000000a', 'gmail',
  'Pepper@Gmail.com', array['https://www.googleapis.com/auth/gmail.readonly'], 'jeton-rafraichissement-A1')) is not null,
  'CX enregistrement de la connexion Gmail de A');
reset role;
select tests.ok((select account_email = 'pepper@gmail.com' and status = 'active' and secret_id is not null
                   from public.external_connections where user_id = 'cccccccc-0000-0000-0000-00000000000a'),
  'CX adresse normalisée, active, secret référencé');
select tests.ok(not exists (select 1 from information_schema.columns where table_name = 'external_connections'
                              and column_name ilike '%token%'),
  'CX aucune colonne de jeton dans la table');
select tests.ok((select count(*) from vault.secrets where secret = 'jeton-rafraichissement-A1') = 1,
  'CX jeton stocké dans Vault');

set role service_role;
select tests.ok((select jeton = 'jeton-rafraichissement-A1' and account_email = 'pepper@gmail.com'
                   from public.jeton_connexion_externe('cccccccc-0000-0000-0000-00000000000a', 'gmail')),
  'CX le backend relit le jeton de A');
select tests.ok((select count(*) from public.jeton_connexion_externe('cccccccc-0000-0000-0000-00000000000b', 'gmail')) = 0,
  'CX aucun jeton pour B');

-- Changement de compte : même ligne, nouveau compte, ancien jeton écrasé
select public.enregistrer_connexion_externe('cccccccc-0000-0000-0000-00000000000a', 'gmail',
  'tony@gmail.com', array['https://www.googleapis.com/auth/gmail.readonly'], 'jeton-rafraichissement-A2');
reset role;
select tests.ok((select count(*) from public.external_connections where user_id = 'cccccccc-0000-0000-0000-00000000000a') = 1,
  'CX une connexion Gmail par utilisateur');
select tests.ok((select count(*) from vault.secrets where secret = 'jeton-rafraichissement-A1') = 0
            and (select count(*) from vault.secrets where secret = 'jeton-rafraichissement-A2') = 1,
  'CX changement de compte : ancien jeton jamais conservé');

-- État à renouveler
set role service_role;
select public.marquer_connexion_externe('cccccccc-0000-0000-0000-00000000000a', 'gmail', 'a_renouveler', 'invalid_grant');
reset role;
select tests.ok((select status = 'a_renouveler' and last_error = 'invalid_grant'
                   from public.external_connections where user_id = 'cccccccc-0000-0000-0000-00000000000a'),
  'CX connexion révoquée : à renouveler');
select tests.erreur($q$update public.external_connections set status = 'perimee'$q$, '23514',
  'CX état inconnu refusé');

-- Client (authenticated) : lecture de SES colonnes non sensibles seulement
set role authenticated;
set request.jwt.claim.sub = 'cccccccc-0000-0000-0000-00000000000a';
select tests.ok((select account_email from public.external_connections) = 'tony@gmail.com',
  'CX A lit sa connexion');
select tests.erreur($q$select secret_id from public.external_connections$q$, '42501',
  'CX le client ne lit pas la référence du secret');
select tests.erreur($q$select * from vault.decrypted_secrets$q$, '42501', 'CX Vault inaccessible au client');
select tests.erreur($q$select * from public.jeton_connexion_externe('cccccccc-0000-0000-0000-00000000000a', 'gmail')$q$,
  '42501', 'CX fonction de jeton interdite au client');
select tests.erreur($q$select public.enregistrer_connexion_externe('cccccccc-0000-0000-0000-00000000000a', 'gmail',
  'x@y.z', '{}', 'jeton-injecte-000')$q$, '42501', 'CX le client n''enregistre pas de connexion');
select tests.erreur($q$update public.external_connections set account_email = 'pirate@x.y'$q$, '42501',
  'CX le client ne modifie rien');
select tests.erreur($q$delete from public.external_connections$q$, '42501', 'CX le client ne supprime rien directement');
set request.jwt.claim.sub = 'cccccccc-0000-0000-0000-00000000000b';
select tests.ok((select count(*) from public.external_connections) = 0, 'CX B ne voit pas la connexion de A');
set role anon;
select tests.erreur($q$select account_email from public.external_connections$q$, '42501', 'CX anon : aucun accès');
reset role;

-- Déconnexion : ligne et secret supprimés
set role service_role;
select tests.ok(public.supprimer_connexion_externe('cccccccc-0000-0000-0000-00000000000a', 'gmail'),
  'CX déconnexion');
select tests.ok(not public.supprimer_connexion_externe('cccccccc-0000-0000-0000-00000000000a', 'gmail'),
  'CX déconnexion idempotente');
reset role;
select tests.ok((select count(*) from vault.secrets where secret like 'jeton-rafraichissement-%') = 0,
  'CX secret Vault supprimé avec la connexion');

-- Compte JARVIS supprimé : connexion et secret supprimés
set role service_role;
select public.enregistrer_connexion_externe('cccccccc-0000-0000-0000-00000000000b', 'gmail', 'b@gmail.com', '{}',
  'jeton-rafraichissement-B1');
reset role;
delete from public.users where id = 'cccccccc-0000-0000-0000-00000000000b';
select tests.ok((select count(*) from vault.secrets where secret = 'jeton-rafraichissement-B1') = 0,
  'CX compte supprimé : secret supprimé');
select tests.erreur($q$select public.enregistrer_connexion_externe('cccccccc-0000-0000-0000-00000000000a', 'gmail',
  'x@y.z', '{}', 'court')$q$, '22023', 'CX jeton invalide refusé');
