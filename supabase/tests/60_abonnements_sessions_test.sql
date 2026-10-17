-- Abonnements, phase 2 : limites effectives, exceptions, sessions, suivi (après 50_*).
\set ON_ERROR_STOP on
reset role;

-- Comptes dédiés (les tests précédents suppriment B) : A = pro (anciennes
-- colonnes 60 / 100 000, sans exception) ; B = free.
insert into auth.users (id, email) values
  ('eeeeeeee-0000-0000-0000-00000000000a', 'abo-a@test.local'),
  ('eeeeeeee-0000-0000-0000-00000000000b', 'abo-b@test.local');
update public.users set plan = 'pro', daily_message_limit = 60, daily_token_limit = 100000
 where id = 'eeeeeeee-0000-0000-0000-00000000000a';
select tests.ok((select bool_and(not limits_override) from public.users),
  'ABO2 aucun compte n''est une exception par défaut');

-- Limites effectives : l'offre, sauf exception explicite ---------------------
select tests.ok((select daily_message_limit = 200 and daily_token_limit = 100000 and llm_provider = 'anthropic'
                   and llm_model = 'claude-opus-5-5' and session_duration_minutes = 300
                   and session_message_limit = 50 and session_token_limit = 30000 and critical_threshold_percent = 80
                   and not limits_override
                   from public.limites_effectives('eeeeeeee-0000-0000-0000-00000000000a')),
  'ABO2 compte Pro aux anciennes valeurs 60 / 100 000 : suit l''offre Pro (200 / 100 000)');
select tests.ok((select daily_message_limit = 100 and daily_token_limit = 50000 and llm_provider = 'groq'
                   from public.limites_effectives('eeeeeeee-0000-0000-0000-00000000000b')),
  'ABO2 compte Free : offre Free (groq, 100 / 50 000)');

update public.plan_config set daily_message_limit = 250 where plan = 'pro';
select tests.ok((select daily_message_limit from public.limites_effectives('eeeeeeee-0000-0000-0000-00000000000a')) = 250,
  'ABO2 une modification de plan_config vaut pour tous les comptes de l''offre');
update public.plan_config set daily_message_limit = 200 where plan = 'pro';

update public.users set limits_override = true, daily_message_limit = 500, daily_token_limit = null
 where id = 'eeeeeeee-0000-0000-0000-00000000000b';
select tests.ok((select daily_message_limit = 500 and daily_token_limit is null and limits_override
                   and session_message_limit = 25
                   from public.limites_effectives('eeeeeeee-0000-0000-0000-00000000000b')),
  'ABO2 exception activée : limites personnelles (NULL = illimité), session de l''offre');
update public.users set limits_override = false, daily_message_limit = 30, daily_token_limit = 50000
 where id = 'eeeeeeee-0000-0000-0000-00000000000b';
select tests.ok((select daily_message_limit from public.limites_effectives('eeeeeeee-0000-0000-0000-00000000000b')) = 100,
  'ABO2 exception désactivée : retour à l''offre');

-- Sessions ------------------------------------------------------------------
select tests.ok(not exists(select 1 from public.session_active('eeeeeeee-0000-0000-0000-00000000000a')),
  'ABO2 aucune session avant le premier appel');
select tests.ok((select ends_at - started_at = interval '300 minutes' and messages_used = 0
                   from public.ouvrir_session('eeeeeeee-0000-0000-0000-00000000000a', 'pro', 300)),
  'ABO2 ouverture : fenêtre de 300 minutes');
select tests.ok((select count(*) from public.usage_sessions where user_id = 'eeeeeeee-0000-0000-0000-00000000000a') = 1
  and (select id from public.ouvrir_session('eeeeeeee-0000-0000-0000-00000000000a', 'pro', 360))
    = (select id from public.session_active('eeeeeeee-0000-0000-0000-00000000000a'))
  and (select ends_at - started_at from public.session_active('eeeeeeee-0000-0000-0000-00000000000a')) = interval '300 minutes',
  'ABO2 session en cours reprise (même session, durée inchangée malgré 360)');
select public.increment_session_usage((select id from public.session_active('eeeeeeee-0000-0000-0000-00000000000a')),
  'eeeeeeee-0000-0000-0000-00000000000a', 1, 1200);
select public.increment_session_usage((select id from public.session_active('eeeeeeee-0000-0000-0000-00000000000a')),
  'eeeeeeee-0000-0000-0000-00000000000b', 5, 5);
select tests.ok((select messages_used = 1 and tokens_used = 1200 from public.session_active('eeeeeeee-0000-0000-0000-00000000000a')),
  'ABO2 consommation comptée (et jamais par un autre compte)');
update public.usage_sessions set started_at = now() - interval '6 hours', ends_at = now() - interval '1 hour'
 where user_id = 'eeeeeeee-0000-0000-0000-00000000000a';
select tests.ok((select messages_used = 0 and ends_at - started_at = interval '360 minutes'
                   from public.ouvrir_session('eeeeeeee-0000-0000-0000-00000000000a', 'pro', 360)),
  'ABO2 session expirée : nouvelle session, avec la nouvelle durée');
select tests.ok((select count(*) from public.usage_sessions where user_id = 'eeeeeeee-0000-0000-0000-00000000000a') = 2,
  'ABO2 ancienne session gardée (historique)');
select tests.erreur($q$select public.ouvrir_session('eeeeeeee-0000-0000-0000-00000000000a', 'pro', 0)$q$,
  '22023', 'ABO2 durée nulle refusée');

-- Suivi par fournisseur -----------------------------------------------------------
select public.increment_llm_usage('eeeeeeee-0000-0000-0000-00000000000a', 'anthropic', 'claude-opus-5-5', 1, 300, 80);
select public.increment_llm_usage('eeeeeeee-0000-0000-0000-00000000000a', 'anthropic', 'claude-opus-5-5', 1, 200, 20);
select tests.ok((select requests = 2 and tokens_input = 500 and tokens_output = 100 from public.llm_usage
                   where user_id = 'eeeeeeee-0000-0000-0000-00000000000a'),
  'ABO2 suivi cumulé par jour, fournisseur et modèle');
select tests.ok((select daily_message_limit from admin.limites_appliquees
                  where user_id = 'eeeeeeee-0000-0000-0000-00000000000a') = 200
  and (select tokens_input from admin.consommation_llm where llm_provider = 'anthropic') = 500,
  'ABO2 vues d''administration');

-- Droits ----------------------------------------------------------------------------
set role authenticated;
set request.jwt.claim.sub = 'eeeeeeee-0000-0000-0000-00000000000a';
select tests.ok((select daily_message_limit = 200 and messages_used >= 0 from public.get_my_quota()),
  'ABO2 get_my_quota : limites effectives');
select tests.ok((select count(*) from public.usage_sessions) = 2, 'ABO2 l''utilisateur lit ses sessions');
select tests.erreur($q$update public.users set limits_override = true$q$, '42501',
  'ABO2 l''utilisateur ne s''accorde pas d''exception');
select tests.erreur($q$select public.limites_effectives('eeeeeeee-0000-0000-0000-00000000000b')$q$, '42501',
  'ABO2 limites d''un autre compte : interdit');
select tests.erreur($q$select public.ouvrir_session('eeeeeeee-0000-0000-0000-00000000000a', 'pro', 1)$q$, '42501',
  'ABO2 ouvrir une session : réservé au backend');
select tests.erreur($q$select public.increment_session_usage(gen_random_uuid(), 'eeeeeeee-0000-0000-0000-00000000000a', -5, -5)$q$,
  '42501', 'ABO2 consommation de session : réservée au backend');
select tests.erreur($q$update public.usage_sessions set messages_used = 0$q$, '42501', 'ABO2 sessions non modifiables');
select tests.erreur('select * from public.llm_usage', '42501', 'ABO2 suivi des coûts non lisible par l''utilisateur');
select tests.erreur('select * from admin.limites_appliquees', '42501', 'ABO2 vue admin non lisible');
set request.jwt.claim.sub = 'eeeeeeee-0000-0000-0000-00000000000b';
select tests.ok((select count(*) from public.usage_sessions) = 0, 'ABO2 sessions d''un autre compte invisibles');
reset role;
set role service_role;
select tests.ok((select daily_message_limit from public.limites_effectives('eeeeeeee-0000-0000-0000-00000000000a')) = 200,
  'ABO2 le backend lit les limites effectives');
select tests.erreur($q$update public.usage_sessions set messages_used = 0$q$, '42501',
  'ABO2 le backend passe par les fonctions (pas d''écriture directe)');
reset role;
