-- Tests de public.enregistrer_contexte_whatsapp (phase 2), après
-- 10_contextes_whatsapp_test.sql (fonctions tests.ok / tests.erreur).
\set ON_ERROR_STOP on

insert into auth.users (id, email) values
  ('dddddddd-0000-0000-0000-000000000001', 'd@test.local'),
  ('eeeeeeee-0000-0000-0000-000000000001', 'e@test.local');
insert into public.conversations (id, user_id, title) values
  ('dddddddd-0000-0000-0000-0000000000c1', 'dddddddd-0000-0000-0000-000000000001', 'Capitale de la RDC'),
  ('eeeeeeee-0000-0000-0000-0000000000c1', 'eeeeeeee-0000-0000-0000-000000000001', 'Chat de E');
insert into public.messages (conversation_id, user_id, role, content) values
  ('dddddddd-0000-0000-0000-0000000000c1', 'dddddddd-0000-0000-0000-000000000001', 'user', 'Quelle est la capitale de la RDC ?'),
  ('dddddddd-0000-0000-0000-0000000000c1', 'dddddddd-0000-0000-0000-000000000001', 'assistant', 'Kinshasa.');

-- Le client ne peut pas appeler la fonction.
set role authenticated;
select tests.erreur($q$
  select public.enregistrer_contexte_whatsapp(
    'dddddddd-0000-0000-0000-000000000001', gen_random_uuid(), gen_random_uuid(),
    null, 'x', '{"contact_name":"X"}', '[{"message_order":0}]')$q$,
  '42501', 'P2. fonction interdite au client');
reset role;

set role service_role;

-- Cas A : chat existant, 3 messages (un sans date), ordre conservé.
select tests.ok(
  (public.enregistrer_contexte_whatsapp(
    'dddddddd-0000-0000-0000-000000000001',
    'dddddddd-0000-0000-0000-00000000c0a1',
    'dddddddd-0000-0000-0000-0000000000a9',
    'dddddddd-0000-0000-0000-0000000000c1',
    'Analyse cette discussion.',
    '{"contact_name":"Tony Stark","current_user_name":"Pepper Potts","participants":["Tony Stark","Pepper Potts"],"period_start":"2026-10-12T09:00:00","period_end":"2026-10-14T18:00:00"}',
    '[{"message_order":1,"source_order":5,"author":"Pepper Potts","content":"Salut Tony.","sent_at":"2026-10-12T09:05:00","sent_at_raw":"12/10/2026 09:05"},
      {"message_order":0,"source_order":4,"author":"Tony Stark","content":"Salut !","sent_at":"2026-10-12T09:00:00","sent_at_raw":"12/10/2026 09:00"},
      {"message_order":2,"source_order":9,"author":"Tony Stark","content":"","kind":"media","media_type":"image","sent_at":null,"sent_at_raw":"32/13/2026"}]'
  ) ->> 'conversation_created')::boolean = false,
  'P2. cas A : chat existant réutilisé');
select tests.ok(
  (select array_agg(content order by message_order) from public.context_messages
    where context_id = 'dddddddd-0000-0000-0000-00000000c0a1')
  = array['Salut !', 'Salut Tony.', ''],
  'P2. ordre original conservé');
select tests.ok(
  (select count(*) from public.messages
    where conversation_id = 'dddddddd-0000-0000-0000-0000000000c1') = 3
  and (select title from public.conversations
    where id = 'dddddddd-0000-0000-0000-0000000000c1') = 'Tony Stark',
  'P2. cas A : anciens messages gardés, consigne ajoutée, titre du contact');
select tests.ok(
  (select message_id = 'dddddddd-0000-0000-0000-0000000000a9'
          and conversation_id = 'dddddddd-0000-0000-0000-0000000000c1'
     from public.conversation_contexts where id = 'dddddddd-0000-0000-0000-00000000c0a1'),
  'P2. contexte relié à la consigne et au chat');

-- Réessai identique : rien de réinséré.
select tests.ok(
  (public.enregistrer_contexte_whatsapp(
    'dddddddd-0000-0000-0000-000000000001',
    'dddddddd-0000-0000-0000-00000000c0a1',
    'dddddddd-0000-0000-0000-0000000000a9',
    'dddddddd-0000-0000-0000-0000000000c1',
    'Analyse cette discussion.', '{"contact_name":"Tony Stark"}',
    '[{"message_order":0},{"message_order":1},{"message_order":2}]'
  ) -> 'already_saved')::boolean,
  'P2. réessai reconnu');
-- Même identifiant, autre contenu : conflit, jamais « déjà enregistré ».
select tests.erreur($q$
  select public.enregistrer_contexte_whatsapp(
    'dddddddd-0000-0000-0000-000000000001',
    'dddddddd-0000-0000-0000-00000000c0a1',
    'dddddddd-0000-0000-0000-0000000000a9',
    'dddddddd-0000-0000-0000-0000000000c1',
    'Autre chose.', '{"contact_name":"Tony Stark"}', '[{"message_order":0}]')$q$,
  'JVC02', 'P2. même context_id, autre nombre de messages : refusé');
select tests.erreur($q$
  select public.enregistrer_contexte_whatsapp(
    'dddddddd-0000-0000-0000-000000000001',
    'dddddddd-0000-0000-0000-00000000c0a1', gen_random_uuid(),
    'dddddddd-0000-0000-0000-0000000000c1',
    'Analyse cette discussion.', '{"contact_name":"Tony Stark"}',
    '[{"message_order":0},{"message_order":1},{"message_order":2}]')$q$,
  'JVC02', 'P2. même context_id, autre consigne : refusé');
select tests.ok(
  (select count(*) from public.context_messages
    where context_id = 'dddddddd-0000-0000-0000-00000000c0a1') = 3
  and (select count(*) from public.messages
    where conversation_id = 'dddddddd-0000-0000-0000-0000000000c1') = 3,
  'P2. réessai : aucun doublon');

-- Deuxième import dans le même chat.
select public.enregistrer_contexte_whatsapp(
  'dddddddd-0000-0000-0000-000000000001',
  'dddddddd-0000-0000-0000-00000000c0a2', gen_random_uuid(),
  'dddddddd-0000-0000-0000-0000000000c1',
  'Analyse les nouveaux échanges.', '{"contact_name":"Tony Stark"}',
  '[{"message_order":0,"content":"Nouveau"}]');
select tests.ok(
  (select count(*) from public.conversation_contexts
    where conversation_id = 'dddddddd-0000-0000-0000-0000000000c1') = 2,
  'P2. deux contextes dans le même chat');

-- Cas B : accueil vide, conversation créée au nom du contact.
-- (Résultat gardé, puis relu par une autre instruction : la conversation
-- créée n'est visible qu'après l'appel.)
create temp table cas_b as
select public.enregistrer_contexte_whatsapp(
  'dddddddd-0000-0000-0000-000000000001',
  'dddddddd-0000-0000-0000-00000000c0b1', gen_random_uuid(), null,
  'Résume.', '{"contact_name":"Pepper Potts"}',
  '[{"message_order":0,"content":"Bonjour"}]') as r;
select tests.ok(
  (select (r ->> 'conversation_created')::boolean
          and (select title from public.conversations
                where id = (r ->> 'conversation_id')::uuid) = 'Pepper Potts'
          and (select count(*) from public.messages
                where conversation_id = (r ->> 'conversation_id')::uuid) = 1
     from cas_b),
  'P2. cas B : conversation créée au nom du contact, avec la consigne');

-- Atomicité : un message invalide (type inconnu) annule TOUT.
select tests.erreur($q$
  select public.enregistrer_contexte_whatsapp(
    'dddddddd-0000-0000-0000-000000000001',
    'dddddddd-0000-0000-0000-00000000c0c1', 'dddddddd-0000-0000-0000-0000000000a7', null,
    'Analyse.', '{"contact_name":"Happy Hogan"}',
    '[{"message_order":0,"content":"ok"},{"message_order":1,"kind":"inconnu"}]')$q$,
  '23514', 'P2. message invalide refusé');
select tests.ok(
  not exists (select 1 from public.conversation_contexts where id = 'dddddddd-0000-0000-0000-00000000c0c1')
  and not exists (select 1 from public.messages where id = 'dddddddd-0000-0000-0000-0000000000a7')
  and not exists (select 1 from public.conversations where title = 'Happy Hogan'),
  'P2. tout ou rien : ni conversation, ni consigne, ni contexte partiel');

-- Refus.
select tests.erreur($q$
  select public.enregistrer_contexte_whatsapp(
    'dddddddd-0000-0000-0000-000000000001', gen_random_uuid(), gen_random_uuid(),
    'eeeeeeee-0000-0000-0000-0000000000c1', 'Analyse.', '{"contact_name":"X"}',
    '[{"message_order":0}]')$q$,
  'JVC01', 'P2. chat d''un autre compte : introuvable');
select tests.ok(
  (select title from public.conversations where id = 'eeeeeeee-0000-0000-0000-0000000000c1') = 'Chat de E',
  'P2. chat de l''autre compte intact');
select tests.erreur($q$
  select public.enregistrer_contexte_whatsapp(
    'eeeeeeee-0000-0000-0000-000000000001', 'dddddddd-0000-0000-0000-00000000c0a1',
    gen_random_uuid(), null, 'Analyse.', '{"contact_name":"X"}',
    '[{"message_order":0}]')$q$,
  'JVC02', 'P2. identifiant de contexte d''un autre compte refusé');
select tests.erreur($q$
  select public.enregistrer_contexte_whatsapp(
    'dddddddd-0000-0000-0000-000000000001', gen_random_uuid(),
    'dddddddd-0000-0000-0000-0000000000a9', null, 'Analyse.', '{"contact_name":"X"}',
    '[{"message_order":0}]')$q$,
  'JVC03', 'P2. identifiant de consigne déjà utilisé');
select tests.erreur($q$
  select public.enregistrer_contexte_whatsapp(
    'dddddddd-0000-0000-0000-000000000001', gen_random_uuid(), gen_random_uuid(),
    null, 'Analyse.', '{"contact_name":"X"}',
    '[{"message_order":0},{"message_order":2}]')$q$,
  'JVC04', 'P2. ordre avec un trou refusé');
select tests.erreur($q$
  select public.enregistrer_contexte_whatsapp(
    'dddddddd-0000-0000-0000-000000000001', gen_random_uuid(), gen_random_uuid(),
    null, '   ', '{"contact_name":"X"}', '[{"message_order":0}]')$q$,
  'JVC04', 'P2. consigne vide refusée');
select tests.erreur($q$
  select public.enregistrer_contexte_whatsapp(
    'dddddddd-0000-0000-0000-000000000001', gen_random_uuid(), gen_random_uuid(),
    null, 'Analyse.', '{"contact_name":"X"}', '[]')$q$,
  'JVC04', 'P2. aucun message refusé');

-- Grande sélection : 5 000 messages en un appel.
select tests.ok(
  (public.enregistrer_contexte_whatsapp(
    'dddddddd-0000-0000-0000-000000000001', gen_random_uuid(), gen_random_uuid(),
    'dddddddd-0000-0000-0000-0000000000c1', 'Analyse tout.', '{"contact_name":"Tony Stark"}',
    (select jsonb_agg(jsonb_build_object('message_order', i, 'author', 'Tony Stark',
                                         'content', 'message ' || i,
                                         'sent_at', '2026-01-01T00:00:00'::timestamp + i * interval '1 minute'))
       from generate_series(0, 4999) i)
  ) ->> 'messages_count')::integer = 5000,
  'P2. 5 000 messages en un appel');
reset role;

select 'TESTS PHASE 2 PASSÉS' as resultat;
