-- Quotas quotidiens seulement + users ↔ plan_config synchronisés (après 60_*).
\set ON_ERROR_STOP on
reset role;

-- Les tests 50 / 60 ont réactivé une durée de session pour éprouver le
-- mécanisme : on rejoue la vidange de la migration.
update public.plan_config
   set session_duration_minutes = null, session_message_limit = null, session_token_limit = null;

select tests.ok((select bool_and(session_duration_minutes is null and session_message_limit is null
                                 and session_token_limit is null) from public.plan_config),
  'SYN aucune offre n''a de quota de session');
select tests.ok((select session_duration_minutes is null and session_message_limit is null
                   from public.limites_effectives('eeeeeeee-0000-0000-0000-00000000000a')),
  'SYN limites effectives sans session');

-- Comptes dédiés : C = free, D = pro avec exception.
insert into auth.users (id, email) values
  ('eeeeeeee-0000-0000-0000-00000000000c', 'syn-c@test.local'),
  ('eeeeeeee-0000-0000-0000-00000000000d', 'syn-d@test.local');
select tests.ok((select daily_message_limit = 100 and daily_token_limit = 50000
                   from public.users where id = 'eeeeeeee-0000-0000-0000-00000000000c'),
  'SYN compte créé : limites de son offre (Free 100 / 50 000)');
update public.users set plan = 'pro', limits_override = true, daily_message_limit = 999, daily_token_limit = null
 where id = 'eeeeeeee-0000-0000-0000-00000000000d';

-- plan_config modifiée → users suit
update public.plan_config set daily_message_limit = 150, daily_token_limit = 60000 where plan = 'free';
select tests.ok((select daily_message_limit = 150 and daily_token_limit = 60000
                   from public.users where id = 'eeeeeeee-0000-0000-0000-00000000000c'),
  'SYN offre Free modifiée : le compte Free suit (150 / 60 000)');
select tests.ok((select daily_message_limit from public.limites_effectives('eeeeeeee-0000-0000-0000-00000000000c')) = 150,
  'SYN users et limites effectives identiques');

update public.plan_config set daily_message_limit = 300 where plan = 'pro';
select tests.ok((select daily_message_limit = 999 and daily_token_limit is null and limits_override
                   from public.users where id = 'eeeeeeee-0000-0000-0000-00000000000d'),
  'SYN offre Pro modifiée : l''exception garde ses valeurs');
select tests.ok((select daily_message_limit from public.users where id = 'eeeeeeee-0000-0000-0000-00000000000a') = 300,
  'SYN offre Pro modifiée : le compte Pro sans exception suit (300)');

-- users.plan modifié → limites de la nouvelle offre
update public.users set plan = 'pro' where id = 'eeeeeeee-0000-0000-0000-00000000000c';
select tests.ok((select daily_message_limit = 300 and daily_token_limit = 100000
                   from public.users where id = 'eeeeeeee-0000-0000-0000-00000000000c'),
  'SYN Free → Pro : limites Pro recopiées');
update public.users set plan = 'free' where id = 'eeeeeeee-0000-0000-0000-00000000000c';
select tests.ok((select daily_message_limit = 150 and daily_token_limit = 60000
                   from public.users where id = 'eeeeeeee-0000-0000-0000-00000000000c'),
  'SYN Pro → Free : limites Free recopiées');

-- Valeur écrite à la main sans exception : ramenée à l'offre
update public.users set daily_message_limit = 5 where id = 'eeeeeeee-0000-0000-0000-00000000000c';
select tests.ok((select daily_message_limit from public.users where id = 'eeeeeeee-0000-0000-0000-00000000000c') = 150,
  'SYN sans exception, une limite personnelle n''est jamais gardée');

-- Exception retirée : retour à l'offre
update public.users set limits_override = false where id = 'eeeeeeee-0000-0000-0000-00000000000d';
select tests.ok((select daily_message_limit = 300 and daily_token_limit = 100000
                   from public.users where id = 'eeeeeeee-0000-0000-0000-00000000000d'),
  'SYN exception retirée : limites Pro recopiées');

-- Consommation jamais touchée par un changement de limite
insert into public.quota_usage (user_id, usage_date, messages_used, tokens_used)
values ('eeeeeeee-0000-0000-0000-00000000000c', current_date, 7, 1234);
update public.plan_config set daily_message_limit = 120 where plan = 'free';
update public.users set plan = 'pro' where id = 'eeeeeeee-0000-0000-0000-00000000000c';
select tests.ok((select messages_used = 7 and tokens_used = 1234 from public.quota_usage
                   where user_id = 'eeeeeeee-0000-0000-0000-00000000000c' and usage_date = current_date),
  'SYN consommation conservée quand l''offre ou les limites changent');

-- Le client ne peut pas appeler la synchronisation lui-même
select tests.ok(not has_function_privilege('authenticated', 'public.users_suivre_offre()', 'execute')
  and not has_function_privilege('authenticated', 'public.plan_config_propager()', 'execute'),
  'SYN fonctions de synchronisation non appelables par le client');

-- Remise en état pour la suite
update public.plan_config set daily_message_limit = 100, daily_token_limit = 50000 where plan = 'free';
update public.plan_config set daily_message_limit = 200 where plan = 'pro';
