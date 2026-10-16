-- =============================================================================
-- JARVIS — Phase 5.1 WhatsApp : UNE seule réponse déclarée envoyée par
-- ensemble de propositions, garantie par la base
-- =============================================================================
-- Les déclarations (phase 4) sont dans messages.attachments de la réponse
-- de JARVIS qui porte les propositions. Une lecture-modification côté
-- backend laissait deux appareils enregistrer deux choix en même temps.
-- Ces deux fonctions verrouillent la LIGNE de la réponse (select … for
-- update) : les déclarations d'un même ensemble se suivent, jamais deux
-- choix actifs.
--
-- Aucune table ni colonne modifiée. Exécution réservée à service_role.
-- Erreurs : JVC21 réponse introuvable pour ce compte et ce chat.
-- Résultat : {"statut": "ok" | "deja_choisi" | "annulee" | "aucune",
--             "entree": {…déclaration active ou concernée…}}
-- =============================================================================

create or replace function public.declarer_reponse_envoyee(
  p_user_id          uuid,
  p_conversation_id  uuid,
  p_message_id       uuid,
  p_entree           jsonb     -- déclaration complète (type reponse_envoyee)
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_attachments jsonb;
  v_active jsonb;
  v_proposition text := p_entree ->> 'proposition_id';
begin
  if v_proposition is null or (p_entree ->> 'type') is distinct from 'reponse_envoyee' then
    raise exception 'déclaration invalide' using errcode = 'JVC21';
  end if;
  select coalesce(attachments, '[]'::jsonb) into v_attachments
    from public.messages
   where id = p_message_id and user_id = p_user_id
     and conversation_id = p_conversation_id and role = 'assistant'
   for update;
  if not found then
    raise exception 'réponse introuvable' using errcode = 'JVC21';
  end if;

  select e into v_active
    from jsonb_array_elements(v_attachments) e
   where e ->> 'type' = 'reponse_envoyee' and e ->> 'statut' = 'declaree_envoyee'
   limit 1;
  if v_active is not null then
    -- Même proposition : appui répété ou réessai (idempotent).
    return jsonb_build_object(
      'statut', case when v_active ->> 'proposition_id' = v_proposition then 'ok' else 'deja_choisi' end,
      'entree', v_active);
  end if;

  -- Une seule entrée par proposition (l'annulation précédente est remplacée).
  update public.messages
     set attachments = coalesce((
           select jsonb_agg(e) from jsonb_array_elements(v_attachments) e
            where not (e ->> 'type' = 'reponse_envoyee' and e ->> 'proposition_id' = v_proposition)
         ), '[]'::jsonb) || jsonb_build_array(p_entree)
   where id = p_message_id and user_id = p_user_id;
  return jsonb_build_object('statut', 'ok', 'entree', p_entree);
end;
$$;

create or replace function public.annuler_reponse_envoyee(
  p_user_id          uuid,
  p_conversation_id  uuid,
  p_message_id       uuid,
  p_proposition_id   text,
  p_annulee_le       timestamptz
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_attachments jsonb;
  v_entree jsonb;
begin
  select coalesce(attachments, '[]'::jsonb) into v_attachments
    from public.messages
   where id = p_message_id and user_id = p_user_id
     and conversation_id = p_conversation_id and role = 'assistant'
   for update;
  if not found then
    raise exception 'réponse introuvable' using errcode = 'JVC21';
  end if;
  select e into v_entree from jsonb_array_elements(v_attachments) e
   where e ->> 'type' = 'reponse_envoyee' and e ->> 'proposition_id' = p_proposition_id
     and e ->> 'statut' = 'declaree_envoyee';
  if v_entree is null then
    return jsonb_build_object('statut', 'aucune', 'entree', null);
  end if;
  v_entree := v_entree || jsonb_build_object('statut', 'annulee', 'cancelled_at', p_annulee_le);
  update public.messages
     set attachments = (
           select jsonb_agg(case when e ->> 'type' = 'reponse_envoyee'
                                  and e ->> 'proposition_id' = p_proposition_id
                                  and e ->> 'statut' = 'declaree_envoyee'
                                 then v_entree else e end)
             from jsonb_array_elements(v_attachments) e)
   where id = p_message_id and user_id = p_user_id;
  return jsonb_build_object('statut', 'annulee', 'entree', v_entree);
end;
$$;

revoke all on function public.declarer_reponse_envoyee(uuid, uuid, uuid, jsonb) from public, anon, authenticated;
revoke all on function public.annuler_reponse_envoyee(uuid, uuid, uuid, text, timestamptz) from public, anon, authenticated;
grant execute on function public.declarer_reponse_envoyee(uuid, uuid, uuid, jsonb) to service_role;
grant execute on function public.annuler_reponse_envoyee(uuid, uuid, uuid, text, timestamptz) to service_role;
