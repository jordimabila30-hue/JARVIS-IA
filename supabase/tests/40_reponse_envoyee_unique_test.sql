-- Phase 5.1 : une seule réponse déclarée envoyée par ensemble (après 30_*).
\set ON_ERROR_STOP on

insert into public.messages (id, conversation_id, user_id, role, content, attachments) values
  ('dddddddd-0000-0000-0000-0000000005e1', 'dddddddd-0000-0000-0000-0000000000c1',
   'dddddddd-0000-0000-0000-000000000001', 'assistant', 'Voici des idées.',
   '[{"type":"propositions_reponse","mode":"reponse","tons":[]}]');

set role authenticated;
select tests.erreur($q$
  select public.declarer_reponse_envoyee('dddddddd-0000-0000-0000-000000000001',
    'dddddddd-0000-0000-0000-0000000000c1', 'dddddddd-0000-0000-0000-0000000005e1',
    '{"type":"reponse_envoyee","statut":"declaree_envoyee","proposition_id":"p1"}')$q$,
  '42501', 'P5.1 fonction interdite au client');
reset role;
set role service_role;

select tests.ok(
  public.declarer_reponse_envoyee('dddddddd-0000-0000-0000-000000000001',
    'dddddddd-0000-0000-0000-0000000000c1', 'dddddddd-0000-0000-0000-0000000005e1',
    '{"type":"reponse_envoyee","statut":"declaree_envoyee","proposition_id":"p1","texte":"Un"}') ->> 'statut' = 'ok',
  'P5.1 première déclaration');
select tests.ok(
  public.declarer_reponse_envoyee('dddddddd-0000-0000-0000-000000000001',
    'dddddddd-0000-0000-0000-0000000000c1', 'dddddddd-0000-0000-0000-0000000005e1',
    '{"type":"reponse_envoyee","statut":"declaree_envoyee","proposition_id":"p1","texte":"Un"}') ->> 'statut' = 'ok',
  'P5.1 même proposition : idempotent');
select tests.ok(
  public.declarer_reponse_envoyee('dddddddd-0000-0000-0000-000000000001',
    'dddddddd-0000-0000-0000-0000000000c1', 'dddddddd-0000-0000-0000-0000000005e1',
    '{"type":"reponse_envoyee","statut":"declaree_envoyee","proposition_id":"p2","texte":"Deux"}') ->> 'statut' = 'deja_choisi',
  'P5.1 autre proposition refusée tant qu''un choix est actif');
select tests.ok(
  (select count(*) from public.messages m, jsonb_array_elements(m.attachments) e
    where m.id = 'dddddddd-0000-0000-0000-0000000005e1' and e ->> 'type' = 'reponse_envoyee') = 1
  and (select count(*) from public.messages m, jsonb_array_elements(m.attachments) e
        where m.id = 'dddddddd-0000-0000-0000-0000000005e1' and e ->> 'type' = 'propositions_reponse') = 1,
  'P5.1 une seule déclaration, propositions intactes');
select tests.ok(
  public.annuler_reponse_envoyee('dddddddd-0000-0000-0000-000000000001',
    'dddddddd-0000-0000-0000-0000000000c1', 'dddddddd-0000-0000-0000-0000000005e1', 'p1', now()) ->> 'statut' = 'annulee',
  'P5.1 annulation');
select tests.ok(
  public.declarer_reponse_envoyee('dddddddd-0000-0000-0000-000000000001',
    'dddddddd-0000-0000-0000-0000000000c1', 'dddddddd-0000-0000-0000-0000000005e1',
    '{"type":"reponse_envoyee","statut":"declaree_envoyee","proposition_id":"p2","texte":"Deux"}') ->> 'statut' = 'ok',
  'P5.1 après annulation, un autre choix est possible');
select tests.ok(
  (select array_agg((e ->> 'proposition_id') || ':' || (e ->> 'statut') order by e ->> 'proposition_id')
     from public.messages m, jsonb_array_elements(m.attachments) e
    where m.id = 'dddddddd-0000-0000-0000-0000000005e1' and e ->> 'type' = 'reponse_envoyee')
  = array['p1:annulee', 'p2:declaree_envoyee'],
  'P5.1 historique : annulation gardée, un seul choix actif');
select tests.erreur($q$
  select public.declarer_reponse_envoyee('eeeeeeee-0000-0000-0000-000000000001',
    'dddddddd-0000-0000-0000-0000000000c1', 'dddddddd-0000-0000-0000-0000000005e1',
    '{"type":"reponse_envoyee","statut":"declaree_envoyee","proposition_id":"p3"}')$q$,
  'JVC21', 'P5.1 autre compte refusé');
select tests.ok(
  public.annuler_reponse_envoyee('dddddddd-0000-0000-0000-000000000001',
    'dddddddd-0000-0000-0000-0000000000c1', 'dddddddd-0000-0000-0000-0000000005e1', 'p9', now()) ->> 'statut' = 'aucune',
  'P5.1 annuler une proposition non choisie : rien');
reset role;
