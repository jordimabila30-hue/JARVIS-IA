-- Abonnements Free & Pro, phase 1 : public.plan_config (après 40_*).
\set ON_ERROR_STOP on

-- La migration 20261017200000 a vidé les sessions (quotas quotidiens
-- seulement) ; le mécanisme de session reste éprouvé par 50 et 60 avec les
-- valeurs de la phase 1, puis 70 les vide de nouveau.
update public.plan_config set session_duration_minutes = 300, session_message_limit = 25,
  session_token_limit = 15000 where plan = 'free';
update public.plan_config set session_duration_minutes = 300, session_message_limit = 50,
  session_token_limit = 30000 where plan = 'pro';

-- Valeurs initiales -----------------------------------------------------------
select tests.ok((select count(*) from public.plan_config) = 2, 'ABO une ligne par abonnement (free, pro)');
select tests.ok(exists(select 1 from public.plan_config
  where plan = 'free' and llm_provider = 'groq' and llm_model = 'openai/gpt-oss-120b'
    and daily_message_limit = 100 and daily_token_limit = 50000 and session_duration_minutes = 300
    and session_message_limit = 25 and session_token_limit = 15000 and critical_threshold_percent = 80),
  'ABO valeurs Free');
select tests.ok(exists(select 1 from public.plan_config
  where plan = 'pro' and llm_provider = 'anthropic' and llm_model = 'claude-opus-5-5'
    and daily_message_limit = 200 and daily_token_limit = 100000 and session_duration_minutes = 300
    and session_message_limit = 50 and session_token_limit = 30000 and critical_threshold_percent = 80),
  'ABO valeurs Pro');

-- Utilisateurs ordinaires : aucun accès -----------------------------------------
set role authenticated;
select tests.erreur('select * from public.plan_config', '42501', 'ABO lecture interdite (authenticated)');
select tests.erreur($q$update public.plan_config set daily_message_limit = 999$q$, '42501',
  'ABO modification interdite (authenticated)');
select tests.erreur($q$insert into public.plan_config values ('free','groq','x',1,1,1,1,1,1)$q$, '42501',
  'ABO ajout interdit (authenticated)');
select tests.erreur('delete from public.plan_config', '42501', 'ABO suppression interdite (authenticated)');
select tests.erreur('truncate public.plan_config', '42501', 'ABO TRUNCATE interdit (authenticated)');
select tests.erreur($q$update public.users set plan = 'pro'$q$, '42501',
  'ABO un utilisateur ne change pas son abonnement');
select tests.erreur($q$update public.users set daily_message_limit = 9999$q$, '42501',
  'ABO un utilisateur ne change pas ses limites');
reset role;
set role anon;
select tests.erreur('select * from public.plan_config', '42501', 'ABO lecture interdite (anon)');
reset role;

-- Backend (service_role) : lecture seule -----------------------------------------
set role service_role;
select tests.ok((select daily_message_limit from public.plan_config where plan = 'free') = 100,
  'ABO lecture par le backend');
select tests.erreur($q$update public.plan_config set daily_message_limit = 1$q$, '42501',
  'ABO le backend ne modifie pas les offres');
reset role;

-- Administrateur (tableau de bord) : modification, contraintes ------------------
update public.plan_config set updated_at = now() - interval '1 day' where plan = 'free';
update public.plan_config set daily_message_limit = 150, session_duration_minutes = 360 where plan = 'free';
select tests.ok(exists(select 1 from public.plan_config where plan = 'free'
  and daily_message_limit = 150 and session_duration_minutes = 360 and updated_at > now() - interval '1 minute'),
  'ABO modification par l''administrateur, updated_at automatique');
select tests.erreur($q$update public.plan_config set critical_threshold_percent = 120 where plan = 'free'$q$,
  '23514', 'ABO seuil > 100 refusé');
select tests.erreur($q$update public.plan_config set llm_provider = 'openai' where plan = 'free'$q$,
  '23514', 'ABO fournisseur inconnu refusé');
select tests.erreur($q$update public.plan_config set llm_model = '  ' where plan = 'free'$q$,
  '23514', 'ABO modèle vide refusé');
select tests.erreur($q$update public.plan_config set session_duration_minutes = 0 where plan = 'free'$q$,
  '23514', 'ABO durée de session nulle refusée');
select tests.erreur($q$update public.plan_config set session_message_limit = 151 where plan = 'free'$q$,
  '23514', 'ABO session au-delà de la journée refusée');
select tests.erreur($q$update public.plan_config set daily_token_limit = -1 where plan = 'free'$q$,
  '23514', 'ABO limite négative refusée');
select tests.erreur($q$update public.plan_config set daily_token_limit = null where plan = 'free'$q$,
  '23502', 'ABO cellule vide refusée (jamais « illimité » par erreur)');
select tests.erreur($q$insert into public.plan_config values ('pro','anthropic','x',1,1,1,1,1,1)$q$,
  '23505', 'ABO une seule configuration par abonnement');
select tests.erreur($q$insert into public.plan_config values ('gold','anthropic','x',1,1,1,1,1,1)$q$,
  '22P02', 'ABO abonnement inconnu refusé');
update public.plan_config set daily_message_limit = 100, session_duration_minutes = 300 where plan = 'free';

-- Ré-exécution de la migration (faite deux fois par lancer_tests.sh) : la
-- valeur modifiée ci-dessus aurait été gardée (ON CONFLICT DO NOTHING).
select tests.ok(not has_table_privilege('authenticated', 'public.plan_config', 'truncate')
  and not has_table_privilege('anon', 'public.plan_config', 'select')
  and (select relrowsecurity from pg_class where oid = 'public.plan_config'::regclass),
  'ABO droits retirés et RLS active');
