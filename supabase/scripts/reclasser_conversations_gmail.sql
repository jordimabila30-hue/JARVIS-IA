-- K1 (G3 / K1-15) : reclasser sous Gmail les conversations ANTÉRIEURES au
-- marqueur `{"type": "source", "source": "gmail"}`.
--
-- Avant K1, rien n'était enregistré quand Gmail servait : ces conversations
-- ne sont reconnaissables que par leur texte (heuristique). À relire, puis
-- exécuter SEULEMENT avec l'accord du propriétaire du projet.
--
-- 1) Aperçu (aucune écriture) : réponses de JARVIS qui citent clairement
--    des e-mails lus, dans une conversation sans marqueur ni contexte WhatsApp.
select c.id as conversation, c.user_id, count(*) as reponses
from public.conversations c
join public.messages m on m.conversation_id = c.id and m.user_id = c.user_id
where m.role = 'assistant'
  and m.content ~* '(e-?mail|mail|courriel|gmail|boîte de réception)'
  and exists (select 1 from public.messages q
              where q.conversation_id = c.id and q.role = 'user'
                and q.content ~* '(mes (e-?)?mails|mon gmail|ma boîte|non lus|courriel)')
  and not exists (select 1 from public.messages x
                  where x.conversation_id = c.id
                    and x.attachments @> '[{"type":"source","source":"gmail"}]')
  and not exists (select 1 from public.conversation_contexts cc where cc.conversation_id = c.id)
group by c.id, c.user_id;

-- 2) Reclassement (à décommenter après vérification de l'aperçu) : le
--    marqueur est ajouté à la DERNIÈRE réponse de chaque conversation retenue.
-- update public.messages m
-- set attachments = coalesce(m.attachments, '[]'::jsonb) || '[{"type":"source","source":"gmail"}]'::jsonb
-- where m.id in (
--   select distinct on (m2.conversation_id) m2.id
--   from public.messages m2
--   where m2.role = 'assistant' and m2.conversation_id in (/* ids de l'aperçu */)
--   order by m2.conversation_id, m2.created_at desc);
