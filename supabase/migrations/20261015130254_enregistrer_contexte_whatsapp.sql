-- =============================================================================
-- JARVIS — Phase 2 du stockage WhatsApp : enregistrement transactionnel
-- =============================================================================
-- Une seule fonction, appelée par le backend (service_role) en UN appel :
-- conversation (reprise ou créée), consigne de l'utilisateur, contexte et
-- messages WhatsApp sélectionnés sont enregistrés dans la MÊME transaction.
-- Une erreur à n'importe quelle étape annule tout : jamais de pièce jointe
-- partielle (ex. 15 messages sur 35) présentée comme complète.
--
-- Idempotence : p_context_id est choisi par l'appareil, une fois par pièce
-- jointe. Un réessai (réseau coupé après l'enregistrement) retrouve le
-- contexte et renvoie ce qui existe, sans rien réinsérer. Un contexte
-- existant est toujours complet (tout ou rien).
--
-- Propriétaire : p_user_id vient du JWT vérifié par le backend, jamais du
-- client. La fonction vérifie elle-même la conversation ; les clés
-- composites de la phase 1 font le reste.
--
-- Aucune table modifiée. Exécution réservée à service_role.
-- Erreurs (code SQLSTATE, lu par le backend) :
--   JVC01 conversation introuvable pour ce compte
--   JVC02 identifiant de contexte déjà utilisé par un autre compte
--   JVC03 identifiant de consigne déjà utilisé
--   JVC04 données invalides (consigne, messages, ordre)
-- =============================================================================

create or replace function public.enregistrer_contexte_whatsapp(
  p_user_id          uuid,
  p_context_id       uuid,
  p_message_id       uuid,
  p_conversation_id  uuid,      -- null : nouvelle conversation (accueil vide)
  p_consigne         text,
  p_contexte         jsonb,     -- métadonnées du contexte
  p_messages         jsonb      -- messages sélectionnés, rangs 0..n-1
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_existant        record;
  v_conversation    uuid;
  v_nouvelle        boolean := false;
  v_nombre          integer;
  v_titre           text;
begin
  -- Réessai : le contexte existe déjà (il est complet, tout ou rien).
  select x.user_id, x.conversation_id, x.message_id
    into v_existant
    from public.conversation_contexts x
   where x.id = p_context_id;
  if found then
    if v_existant.user_id <> p_user_id then
      raise exception 'Identifiant de contexte déjà utilisé' using errcode = 'JVC02';
    end if;
    -- Un réessai renvoie exactement la même pièce jointe : même consigne,
    -- même nombre de messages. Sinon, l'identifiant est réutilisé pour un
    -- autre contenu : refusé (jamais présenté comme enregistré).
    if v_existant.message_id is distinct from p_message_id
       or (select count(*) from public.context_messages m where m.context_id = p_context_id)
          <> coalesce(jsonb_array_length(p_messages), -1) then
      raise exception 'Identifiant de contexte déjà utilisé pour un autre contenu'
        using errcode = 'JVC02';
    end if;
    return jsonb_build_object(
      'already_saved',        true,
      'conversation_id',      v_existant.conversation_id,
      'message_id',           v_existant.message_id,
      'context_id',           p_context_id,
      'conversation_created', false,
      'messages_count',       (select count(*) from public.context_messages m
                                where m.context_id = p_context_id)
    );
  end if;

  -- Validation (le backend valide déjà ; la base ne fait pas confiance).
  if p_consigne is null or char_length(btrim(p_consigne)) = 0
     or char_length(p_consigne) > 8000 then
    raise exception 'Consigne invalide' using errcode = 'JVC04';
  end if;
  if p_messages is null or jsonb_typeof(p_messages) <> 'array'
     or jsonb_array_length(p_messages) = 0 then
    raise exception 'Aucun message sélectionné' using errcode = 'JVC04';
  end if;
  v_nombre := jsonb_array_length(p_messages);
  -- Rangs exactement 0..n-1 (ordre cohérent, sans trou ni doublon).
  if (select count(distinct (e ->> 'message_order')::integer)
            filter (where (e ->> 'message_order')::integer between 0 and v_nombre - 1)
        from jsonb_array_elements(p_messages) e) <> v_nombre then
    raise exception 'Ordre des messages incohérent' using errcode = 'JVC04';
  end if;
  v_titre := left(btrim(coalesce(p_contexte ->> 'contact_name', '')), 200);
  if char_length(v_titre) = 0 then
    raise exception 'Nom du contact manquant' using errcode = 'JVC04';
  end if;

  -- La consigne ne doit pas réutiliser l'identifiant d'un autre message.
  if exists (select 1 from public.messages where id = p_message_id) then
    raise exception 'Identifiant de consigne déjà utilisé' using errcode = 'JVC03';
  end if;

  -- Conversation : reprise (cas A) ou créée (cas B), au nom du contact.
  if p_conversation_id is not null then
    update public.conversations
       set title = v_titre
     where id = p_conversation_id and user_id = p_user_id
    returning id into v_conversation;
    if v_conversation is null then
      raise exception 'Conversation introuvable' using errcode = 'JVC01';
    end if;
  else
    insert into public.conversations (user_id, title)
    values (p_user_id, v_titre)
    returning id into v_conversation;
    v_nouvelle := true;
  end if;

  -- Consigne : un message ordinaire de l'utilisateur.
  insert into public.messages (id, conversation_id, user_id, role, content)
  values (p_message_id, v_conversation, p_user_id, 'user', p_consigne);

  -- Contexte, relié à la conversation et à la consigne.
  insert into public.conversation_contexts (
    id, user_id, conversation_id, message_id, source, contact_name, is_group,
    current_user_name, participants, period_start, period_end,
    dates_uncertain, source_fingerprint
  )
  values (
    p_context_id, p_user_id, v_conversation, p_message_id,
    coalesce(p_contexte ->> 'source', 'whatsapp'),
    v_titre,
    coalesce((p_contexte ->> 'is_group')::boolean, false),
    nullif(p_contexte ->> 'current_user_name', ''),
    coalesce(p_contexte -> 'participants', '[]'::jsonb),
    (p_contexte ->> 'period_start')::timestamp,
    (p_contexte ->> 'period_end')::timestamp,
    coalesce((p_contexte ->> 'dates_uncertain')::boolean, false),
    nullif(p_contexte ->> 'source_fingerprint', '')
  );

  -- Messages sélectionnés : une seule insertion groupée.
  insert into public.context_messages (
    context_id, user_id, message_order, source_order, author, content, kind,
    media_type, sent_at, sent_at_raw
  )
  select p_context_id, p_user_id, m.message_order, m.source_order, m.author,
         coalesce(m.content, ''), coalesce(m.kind, 'text'), m.media_type,
         m.sent_at, coalesce(m.sent_at_raw, '')
    from jsonb_to_recordset(p_messages) as m (
      message_order integer, source_order integer, author text, content text,
      kind text, media_type text, sent_at timestamp, sent_at_raw text
    );

  return jsonb_build_object(
    'already_saved',        false,
    'conversation_id',      v_conversation,
    'message_id',           p_message_id,
    'context_id',           p_context_id,
    'conversation_created', v_nouvelle,
    'messages_count',       v_nombre
  );
end;
$$;

revoke all on function public.enregistrer_contexte_whatsapp(uuid, uuid, uuid, uuid, text, jsonb, jsonb)
  from public, anon, authenticated;
grant execute on function public.enregistrer_contexte_whatsapp(uuid, uuid, uuid, uuid, text, jsonb, jsonb)
  to service_role;
