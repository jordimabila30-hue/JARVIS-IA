-- Tests de la phase 5 (ajouts manuels), après 20_enregistrer_contexte_test.sql
-- (contexte c0a1 du compte d : 3 messages d'export, rangs 0..2).
\set ON_ERROR_STOP on

-- Le client ne peut pas appeler la fonction.
set role authenticated;
select tests.erreur($q$
  select public.ajouter_messages_contexte('dddddddd-0000-0000-0000-000000000001',
    'dddddddd-0000-0000-0000-00000000c0a1',
    '[{"id":"11111111-5555-0000-0000-000000000001","origin":"manual_received","author":"Tony Stark","content":"x"}]')$q$,
  '42501', 'P5. fonction interdite au client');
reset role;

set role service_role;

select tests.ok(
  (select origin from public.context_messages where context_id = 'dddddddd-0000-0000-0000-00000000c0a1'
    and message_order = 0) = 'export',
  'P5. messages existants : provenance export');

-- Deux messages (reçu puis envoyé), dans l'ordre confirmé, date absente.
select tests.ok(
  jsonb_array_length(public.ajouter_messages_contexte('dddddddd-0000-0000-0000-000000000001',
    'dddddddd-0000-0000-0000-00000000c0a1',
    '[{"id":"11111111-5555-0000-0000-000000000001","origin":"manual_received","author":"Tony Stark","content":"Ah bon ? Et tu comptais me le dire quand ?"},
      {"id":"11111111-5555-0000-0000-000000000002","origin":"manual_sent","author":"Pepper Potts","content":"Finalement je serai disponible samedi.","sent_at":"2026-10-16T09:12:00","sent_at_raw":"16/10/2026 09:12"}]')) = 2,
  'P5. deux messages ajoutés');
select tests.ok(
  (select array_agg(message_order || ':' || origin || ':' || author order by message_order)
     from public.context_messages where context_id = 'dddddddd-0000-0000-0000-00000000c0a1')
  = array['0:export:Tony Stark', '1:export:Pepper Potts', '2:export:Tony Stark',
          '3:manual_received:Tony Stark', '4:manual_sent:Pepper Potts'],
  'P5. rangs suivants, ordre confirmé, auteurs et provenance gardés');
select tests.ok(
  (select sent_at is null and sent_at_raw = '' from public.context_messages
    where id = '11111111-5555-0000-0000-000000000001'),
  'P5. date inconnue : rien d''inventé');

-- Réessai (réseau coupé) : rien n'est dupliqué.
select tests.ok(
  jsonb_array_length(public.ajouter_messages_contexte('dddddddd-0000-0000-0000-000000000001',
    'dddddddd-0000-0000-0000-00000000c0a1',
    '[{"id":"11111111-5555-0000-0000-000000000001","origin":"manual_received","author":"Tony Stark","content":"Ah bon ? Et tu comptais me le dire quand ?"},
      {"id":"11111111-5555-0000-0000-000000000002","origin":"manual_sent","author":"Pepper Potts","content":"Finalement je serai disponible samedi."}]')) = 2
  and (select count(*) from public.context_messages where context_id = 'dddddddd-0000-0000-0000-00000000c0a1') = 5,
  'P5. réessai idempotent');

-- Tout ou rien : un message invalide annule l'ensemble.
select tests.erreur($q$
  select public.ajouter_messages_contexte('dddddddd-0000-0000-0000-000000000001',
    'dddddddd-0000-0000-0000-00000000c0a1',
    '[{"id":"11111111-5555-0000-0000-000000000003","origin":"manual_received","author":"Tony Stark","content":"Valide"},
      {"id":"11111111-5555-0000-0000-000000000004","origin":"manual_received","author":"","content":"Sans auteur"}]')$q$,
  'JVC12', 'P5. message invalide refusé');
select tests.ok(
  not exists (select 1 from public.context_messages where id = '11111111-5555-0000-0000-000000000003'),
  'P5. écriture atomique : rien d''inséré');
select tests.erreur($q$
  select public.ajouter_messages_contexte('dddddddd-0000-0000-0000-000000000001',
    'dddddddd-0000-0000-0000-00000000c0a1',
    '[{"id":"11111111-5555-0000-0000-000000000005","origin":"export","author":"Tony Stark","content":"Faux export"}]')$q$,
  'JVC12', 'P5. impossible de créer un faux message d''export');

-- Isolation : le compte e ne peut ni ajouter au contexte de d, ni réutiliser un identifiant.
select tests.erreur($q$
  select public.ajouter_messages_contexte('eeeeeeee-0000-0000-0000-000000000001',
    'dddddddd-0000-0000-0000-00000000c0a1',
    '[{"id":"11111111-5555-0000-0000-000000000006","origin":"manual_received","author":"X","content":"Intrus"}]')$q$,
  'JVC11', 'P5. contexte d''un autre compte refusé');

-- Les messages d'export ne sont pas modifiables ; les messages manuels oui.
select tests.erreur($q$
  update public.context_messages set content = 'falsifié'
   where context_id = 'dddddddd-0000-0000-0000-00000000c0a1' and message_order = 0$q$,
  'JVC13', 'P5. message d''export protégé');
update public.context_messages set content = 'Finalement je serai libre samedi.', edited_at = now()
 where id = '11111111-5555-0000-0000-000000000002';
select tests.ok(
  (select content from public.context_messages where id = '11111111-5555-0000-0000-000000000002')
  = 'Finalement je serai libre samedi.',
  'P5. message manuel corrigé');
select tests.erreur($q$
  update public.context_messages set origin = 'export' where id = '11111111-5555-0000-0000-000000000002'$q$,
  'JVC13', 'P5. provenance d''un ajout non transformable en export');
delete from public.context_messages where id = '11111111-5555-0000-0000-000000000001';
select tests.ok(
  (select count(*) from public.context_messages where context_id = 'dddddddd-0000-0000-0000-00000000c0a1') = 4,
  'P5. ajout supprimé');
-- Après une suppression, l'ajout suivant prend toujours un rang libre.
select tests.ok(
  (public.ajouter_messages_contexte('dddddddd-0000-0000-0000-000000000001',
    'dddddddd-0000-0000-0000-00000000c0a1',
    '[{"id":"11111111-5555-0000-0000-000000000007","origin":"manual_received","author":"Tony Stark","content":"Encore là ?"}]')
   -> 0 ->> 'message_order')::int = 5,
  'P5. rang suivant après suppression');
reset role;
