-- Données « déjà en production » créées AVANT la migration : deux comptes,
-- leurs conversations et messages (dont une réponse de l'assistant).
insert into auth.users (id, email) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'a@test.local'),
  ('bbbbbbbb-0000-0000-0000-000000000001', 'b@test.local');

insert into public.conversations (id, user_id, title) values
  ('aaaaaaaa-0000-0000-0000-0000000000c1', 'aaaaaaaa-0000-0000-0000-000000000001', 'Capitale de la RDC'),
  ('bbbbbbbb-0000-0000-0000-0000000000c1', 'bbbbbbbb-0000-0000-0000-000000000001', 'Conversation de B');

insert into public.messages (id, conversation_id, user_id, role, content) values
  ('aaaaaaaa-0000-0000-0000-0000000000a1', 'aaaaaaaa-0000-0000-0000-0000000000c1',
   'aaaaaaaa-0000-0000-0000-000000000001', 'user', 'Analyse cette discussion.'),
  ('aaaaaaaa-0000-0000-0000-0000000000a2', 'aaaaaaaa-0000-0000-0000-0000000000c1',
   'aaaaaaaa-0000-0000-0000-000000000001', 'assistant', 'D''accord.'),
  ('bbbbbbbb-0000-0000-0000-0000000000b1', 'bbbbbbbb-0000-0000-0000-0000000000c1',
   'bbbbbbbb-0000-0000-0000-000000000001', 'user', 'Bonjour');
