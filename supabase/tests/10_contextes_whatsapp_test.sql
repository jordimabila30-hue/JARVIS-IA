-- Tests de la migration des contextes WhatsApp, dans un PostgreSQL local
-- jetable (voir 00_simulation_supabase.sql). Chaque vérification lève une
-- erreur si elle échoue (psql -v ON_ERROR_STOP=1) et affiche « OK … ».
\set ON_ERROR_STOP on
set client_min_messages = notice;

create schema tests;
grant usage on schema tests to anon, authenticated, service_role;

-- La requête [q] doit échouer avec le code SQLSTATE [code].
create function tests.erreur(q text, code text, libelle text) returns void
language plpgsql as $$
begin
  execute q;
  raise exception 'ÉCHEC % : aucune erreur (attendu %)', libelle, code;
exception
  when others then
    if sqlstate <> code then
      raise exception 'ÉCHEC % : % (%), attendu %', libelle, sqlerrm, sqlstate, code;
    end if;
    raise notice 'OK %', libelle;
end $$;
grant execute on function tests.erreur(text, text, text)
  to anon, authenticated, service_role;

create function tests.ok(condition boolean, libelle text) returns void
language plpgsql as $$
begin
  if not coalesce(condition, false) then
    raise exception 'ÉCHEC %', libelle;
  end if;
  raise notice 'OK %', libelle;
end $$;
grant execute on function tests.ok(boolean, text)
  to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Données existantes (avant la migration, comme en production)
-- ---------------------------------------------------------------------------
-- Les données sont créées AVANT la migration par 05_donnees_existantes.sql ;
-- on vérifie ici qu'elles sont intactes.
select tests.ok((select count(*) from public.conversations) = 2,
  '1. conversations existantes conservées');
select tests.ok((select count(*) from public.messages) = 3,
  '1. messages existants conservés');
select tests.ok(
  (select count(*) from information_schema.tables
    where table_schema = 'public'
      and table_name in ('conversation_contexts', 'context_messages')) = 2,
  '1. les deux tables existent');

-- ---------------------------------------------------------------------------
-- Écriture par le backend (service_role)
-- ---------------------------------------------------------------------------
set role service_role;

insert into public.conversation_contexts
  (id, user_id, conversation_id, message_id, contact_name, is_group,
   current_user_name, participants, period_start, period_end, source_fingerprint)
values
  ('00000000-0000-0000-0000-00000000c001', 'aaaaaaaa-0000-0000-0000-000000000001',
   'aaaaaaaa-0000-0000-0000-0000000000c1', 'aaaaaaaa-0000-0000-0000-0000000000a1',
   'Tony Stark', false, 'Jordi', '["Tony Stark", "Jordi"]',
   '2026-10-12 09:00', '2026-10-14 18:00', 'wa-0123456789abcdef');
select tests.ok(true, '4. contexte inséré');

-- Messages insérés dans le désordre : l'ordre vient de message_order.
insert into public.context_messages
  (context_id, user_id, message_order, source_order, author, content, kind, sent_at, sent_at_raw)
values
  ('00000000-0000-0000-0000-00000000c001', 'aaaaaaaa-0000-0000-0000-000000000001',
   2, 7, 'Tony Stark', 'Tu es disponible demain ?', 'text', '2026-10-14 18:00', '14/10/2026 18:00'),
  ('00000000-0000-0000-0000-00000000c001', 'aaaaaaaa-0000-0000-0000-000000000001',
   0, 3, 'Tony Stark', 'Salut !', 'text', '2026-10-12 09:00', '12/10/2026 09:00'),
  ('00000000-0000-0000-0000-00000000c001', 'aaaaaaaa-0000-0000-0000-000000000001',
   3, 8, 'Jordi', 'Oui, pourquoi ?', 'text', null, '32/13/2026 25:61'),
  ('00000000-0000-0000-0000-00000000c001', 'aaaaaaaa-0000-0000-0000-000000000001',
   1, 4, 'Jordi', 'Salut Tony.', 'text', '2026-10-12 09:05', '12/10/2026 09:05');
select tests.ok(true, '5. plusieurs messages insérés');

-- Média : seulement sa trace.
insert into public.context_messages
  (context_id, user_id, message_order, author, content, kind, media_type, sent_at_raw)
values
  ('00000000-0000-0000-0000-00000000c001', 'aaaaaaaa-0000-0000-0000-000000000001',
   4, 'Tony Stark', '', 'media', 'image', '14/10/2026 18:01');

-- Second contexte dans la même conversation (import ultérieur).
insert into public.conversation_contexts (id, user_id, conversation_id, contact_name)
values ('00000000-0000-0000-0000-00000000c002', 'aaaaaaaa-0000-0000-0000-000000000001',
        'aaaaaaaa-0000-0000-0000-0000000000c1', 'Tony Stark');
insert into public.context_messages (context_id, user_id, message_order, author, content, sent_at_raw)
values ('00000000-0000-0000-0000-00000000c002', 'aaaaaaaa-0000-0000-0000-000000000001',
        0, 'Tony Stark', 'Nouveau message', '15/10/2026 08:00');
select tests.ok(
  (select count(*) from public.conversation_contexts
    where conversation_id = 'aaaaaaaa-0000-0000-0000-0000000000c1') = 2,
  '7. deux contextes dans le même chat JARVIS');

-- Même service_role ne peut pas rattacher un contexte au chat d'un autre.
select tests.erreur($q$
  insert into public.conversation_contexts (user_id, conversation_id, contact_name)
  values ('aaaaaaaa-0000-0000-0000-000000000001',
          'bbbbbbbb-0000-0000-0000-0000000000c1', 'Intrus')$q$,
  '23503', '5/8. contexte de A sur la conversation de B refusé');
select tests.erreur($q$
  insert into public.conversation_contexts (user_id, conversation_id, message_id, contact_name)
  values ('aaaaaaaa-0000-0000-0000-000000000001',
          'aaaaaaaa-0000-0000-0000-0000000000c1',
          'bbbbbbbb-0000-0000-0000-0000000000b1', 'Intrus')$q$,
  '23503', '5/8. contexte de A sur un message de B refusé');
select tests.erreur($q$
  insert into public.context_messages (context_id, user_id, message_order, content)
  values ('00000000-0000-0000-0000-00000000c001',
          'bbbbbbbb-0000-0000-0000-000000000001', 9, 'Intrus')$q$,
  '23503', '5/8. message de B dans le contexte de A refusé');
select tests.erreur($q$
  insert into public.context_messages (context_id, user_id, message_order, content)
  values ('00000000-0000-0000-0000-00000000c001',
          'aaaaaaaa-0000-0000-0000-000000000001', 0, 'doublon')$q$,
  '23505', '6. deux messages au même rang refusés');
select tests.erreur($q$
  insert into public.conversation_contexts (user_id, conversation_id, source, contact_name)
  values ('aaaaaaaa-0000-0000-0000-000000000001',
          'aaaaaaaa-0000-0000-0000-0000000000c1', 'telegram', 'X')$q$,
  '23514', 'source inconnue refusée');
select tests.erreur($q$
  insert into public.conversation_contexts
    (user_id, conversation_id, contact_name, period_start, period_end)
  values ('aaaaaaaa-0000-0000-0000-000000000001',
          'aaaaaaaa-0000-0000-0000-0000000000c1', 'X',
          '2026-10-14', '2026-10-12')$q$,
  '23514', 'période inversée refusée');
select tests.erreur($q$
  insert into public.conversation_contexts (user_id, conversation_id, contact_name)
  values ('aaaaaaaa-0000-0000-0000-000000000001',
          'aaaaaaaa-0000-0000-0000-0000000000c1', '')$q$,
  '23514', 'nom de contact vide refusé');
reset role;

-- ---------------------------------------------------------------------------
-- Lecture dans l'ordre original, nombre calculé
-- ---------------------------------------------------------------------------
select tests.ok(
  (select array_agg(content order by message_order)
     from public.context_messages
    where context_id = '00000000-0000-0000-0000-00000000c001')
  = array['Salut !', 'Salut Tony.', 'Tu es disponible demain ?', 'Oui, pourquoi ?', ''],
  '6. messages relus dans l''ordre original');
select tests.ok(
  (select messages_count from admin.contextes_lisibles
    where id = '00000000-0000-0000-0000-00000000c001') = 5,
  'nombre de messages calculé (vue admin)');
select tests.ok(
  (select sent_at is null and sent_at_raw = '32/13/2026 25:61'
     from public.context_messages where message_order = 3
      and context_id = '00000000-0000-0000-0000-00000000c001'),
  'date illisible : null, texte d''origine gardé');

-- ---------------------------------------------------------------------------
-- Client (authenticated) : RLS
-- ---------------------------------------------------------------------------
set role authenticated;
set request.jwt.claim.sub = 'aaaaaaaa-0000-0000-0000-000000000001';
select tests.ok((select count(*) from public.conversation_contexts) = 2,
  '3. A voit ses 2 contextes');
select tests.ok((select count(*) from public.context_messages) = 6,
  '3. A voit ses 6 messages WhatsApp');
select tests.erreur($q$
  insert into public.conversation_contexts (user_id, conversation_id, contact_name)
  values ('aaaaaaaa-0000-0000-0000-000000000001',
          'aaaaaaaa-0000-0000-0000-0000000000c1', 'Direct')$q$,
  '42501', '8. le client n''écrit pas directement (backend seulement)');
select tests.erreur($q$
  update public.context_messages set content = 'falsifié'$q$,
  '42501', '8. messages WhatsApp non modifiables par le client');
select tests.erreur($q$truncate public.context_messages$q$,
  '42501', '8. TRUNCATE interdit au client');

set request.jwt.claim.sub = 'bbbbbbbb-0000-0000-0000-000000000001';
select tests.ok((select count(*) from public.conversation_contexts) = 0,
  '8. B ne voit aucun contexte de A');
select tests.ok((select count(*) from public.context_messages) = 0,
  '8. B ne voit aucun message WhatsApp de A');
delete from public.conversation_contexts;  -- RLS : ne touche rien de A
reset role;
select tests.ok((select count(*) from public.conversation_contexts) = 2,
  '8. B ne peut pas supprimer les contextes de A');

set role anon;
select tests.erreur($q$select * from public.conversation_contexts$q$,
  '42501', '8. anonyme : aucun accès');
reset role;

-- ---------------------------------------------------------------------------
-- Suppressions
-- ---------------------------------------------------------------------------
-- Message JARVIS supprimé : le contexte reste, sans lien vers lui.
delete from public.messages where id = 'aaaaaaaa-0000-0000-0000-0000000000a1';
select tests.ok(
  (select message_id is null from public.conversation_contexts
    where id = '00000000-0000-0000-0000-00000000c001'),
  'message JARVIS supprimé : contexte gardé, message_id null');

-- A supprime un contexte : ses messages partent avec lui.
set role authenticated;
set request.jwt.claim.sub = 'aaaaaaaa-0000-0000-0000-000000000001';
delete from public.conversation_contexts where id = '00000000-0000-0000-0000-00000000c002';
reset role;
select tests.ok(
  (select count(*) from public.context_messages
    where context_id = '00000000-0000-0000-0000-00000000c002') = 0,
  '9. contexte supprimé avec ses messages');

-- A supprime sa conversation (comme Flutter aujourd'hui) : plus rien.
set role authenticated;
set request.jwt.claim.sub = 'aaaaaaaa-0000-0000-0000-000000000001';
delete from public.conversations where id = 'aaaaaaaa-0000-0000-0000-0000000000c1';
reset role;
select tests.ok((select count(*) from public.conversation_contexts) = 0
  and (select count(*) from public.context_messages) = 0,
  '10. conversation supprimée : aucun contexte ni message orphelin');
select tests.ok(
  (select count(*) from public.conversations
    where id = 'bbbbbbbb-0000-0000-0000-0000000000c1') = 1
  and (select count(*) from public.messages
    where id = 'bbbbbbbb-0000-0000-0000-0000000000b1') = 1,
  '11. conversation et messages de B intacts');

-- Compte supprimé : tout part en cascade.
insert into public.conversation_contexts (user_id, conversation_id, contact_name)
values ('bbbbbbbb-0000-0000-0000-000000000001',
        'bbbbbbbb-0000-0000-0000-0000000000c1', 'Peter Parker');
delete from auth.users where id = 'bbbbbbbb-0000-0000-0000-000000000001';
select tests.ok((select count(*) from public.conversation_contexts) = 0,
  '10. compte supprimé : contextes supprimés');

-- ---------------------------------------------------------------------------
-- Évolution : une colonne ajoutée ne perd rien
-- ---------------------------------------------------------------------------
insert into auth.users (id, email) values ('cccccccc-0000-0000-0000-000000000001', 'c@test.local');
insert into public.conversations (id, user_id, title)
values ('cccccccc-0000-0000-0000-0000000000c1', 'cccccccc-0000-0000-0000-000000000001', 'C');
insert into public.conversation_contexts (id, user_id, conversation_id, contact_name)
values ('00000000-0000-0000-0000-00000000c003', 'cccccccc-0000-0000-0000-000000000001',
        'cccccccc-0000-0000-0000-0000000000c1', 'Pepper Potts');
alter table public.conversation_contexts add column note_test text;
select tests.ok(
  (select contact_name from public.conversation_contexts
    where id = '00000000-0000-0000-0000-00000000c003') = 'Pepper Potts',
  '12. colonne ajoutée sans perte de données');
alter table public.conversation_contexts drop column note_test;

select 'TOUS LES TESTS SONT PASSÉS' as resultat;
