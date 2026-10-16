-- =============================================================================
-- JARVIS — Phase 5 WhatsApp : actualisation manuelle d'un contexte
-- =============================================================================
-- L'utilisateur colle dans JARVIS la suite de sa conversation WhatsApp
-- (réponse reçue, message qu'il a envoyé) sans réimporter l'export.
--
-- 1. context_messages.origin : provenance OBLIGATOIRE de chaque message
--      export           message lu dans un export WhatsApp (tous les messages
--                       existants : valeur par défaut)
--      manual_received  message reçu, collé par l'utilisateur
--      manual_sent      message envoyé par l'utilisateur, collé par lui
--    (une proposition JARVIS déclarée envoyée reste dans messages.attachments,
--    phase 4 ; declared_proposition_id relie un message collé à elle).
--    Un message collé est une information fournie par l'utilisateur, jamais
--    une réception vérifiée sur WhatsApp.
-- 2. edited_at : dernière correction d'un message manuel.
-- 3. ajouter_messages_contexte : ajout ATOMIQUE de plusieurs messages à la
--    suite d'un contexte (rangs suivants, dans l'ordre confirmé), contexte
--    verrouillé (ajouts simultanés sérialisés), idempotent (identifiants
--    choisis par l'appareil : un réessai ne duplique rien).
-- 4. Les messages d'un export ne sont jamais modifiables par le backend :
--    déclencheur qui refuse toute modification d'une ligne « export » (hors
--    suppression du contexte entier ou d'une ligne par son propriétaire).
--
-- Ré-exécutable. Aucune donnée existante modifiée (origin = 'export').
-- Erreurs : JVC11 contexte introuvable pour ce compte ; JVC12 données
-- invalides ; JVC13 message d'export non modifiable.
-- =============================================================================

alter table public.context_messages
  add column if not exists origin text not null default 'export',
  add column if not exists edited_at timestamptz,
  add column if not exists declared_proposition_id text;

do $$
begin
  if not exists (select 1 from pg_constraint
                  where conrelid = 'public.context_messages'::regclass
                    and conname = 'context_messages_origin_check') then
    alter table public.context_messages
      add constraint context_messages_origin_check
        check (origin in ('export', 'manual_received', 'manual_sent'));
  end if;
  if not exists (select 1 from pg_constraint
                  where conrelid = 'public.context_messages'::regclass
                    and conname = 'context_messages_manual_author_check') then
    -- Un message collé a toujours un auteur choisi (jamais un « événement »).
    alter table public.context_messages
      add constraint context_messages_manual_author_check
        check (origin = 'export' or (author is not null and kind = 'text'));
  end if;
  if not exists (select 1 from pg_constraint
                  where conrelid = 'public.context_messages'::regclass
                    and conname = 'context_messages_declared_check') then
    alter table public.context_messages
      add constraint context_messages_declared_check
        check (declared_proposition_id is null
               or (origin = 'manual_sent' and char_length(declared_proposition_id) <= 100));
  end if;
end$$;

-- Messages ajoutés d'un contexte (consultation, correction).
create index if not exists context_messages_manual_idx
  on public.context_messages (context_id, message_order)
  where origin <> 'export';

-- Les messages d'un export ne changent jamais (seule la suppression reste
-- possible, avec le contexte ou par son propriétaire).
create or replace function public.proteger_messages_export()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.origin = 'export'
     and (new.content, new.author, new.sent_at, new.sent_at_raw, new.kind, new.origin,
          new.message_order)
         is distinct from
         (old.content, old.author, old.sent_at, old.sent_at_raw, old.kind, old.origin,
          old.message_order) then
    raise exception 'message d''export non modifiable' using errcode = 'JVC13';
  end if;
  if old.origin <> 'export' and new.origin = 'export' then
    raise exception 'provenance non modifiable' using errcode = 'JVC13';
  end if;
  return new;
end;
$$;

drop trigger if exists context_messages_proteger_export on public.context_messages;
create trigger context_messages_proteger_export
  before update on public.context_messages
  for each row execute function public.proteger_messages_export();

-- -----------------------------------------------------------------------------
-- Ajout atomique
-- -----------------------------------------------------------------------------
-- p_messages : [{"id": uuid, "origin": "manual_received"|"manual_sent",
--                "author": text, "content": text, "sent_at": ts|null,
--                "sent_at_raw": text, "declared_proposition_id": text|null}]
-- dans l'ordre confirmé par l'utilisateur. Renvoie les lignes de ces
-- identifiants (insérées maintenant ou déjà présentes : réessai).
create or replace function public.ajouter_messages_contexte(
  p_user_id     uuid,
  p_context_id  uuid,
  p_messages    jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_suivant integer;
  v_m jsonb;
  v_id uuid;
begin
  if jsonb_typeof(p_messages) is distinct from 'array'
     or jsonb_array_length(p_messages) = 0
     or jsonb_array_length(p_messages) > 50 then
    raise exception 'messages invalides' using errcode = 'JVC12';
  end if;

  -- Verrou du contexte : deux ajouts simultanés se suivent, sans rang commun.
  perform 1 from public.conversation_contexts
   where id = p_context_id and user_id = p_user_id
   for update;
  if not found then
    raise exception 'contexte introuvable' using errcode = 'JVC11';
  end if;

  select coalesce(max(message_order), -1) + 1 into v_suivant
    from public.context_messages where context_id = p_context_id;

  for v_m in select * from jsonb_array_elements(p_messages) loop
    v_id := (v_m ->> 'id')::uuid;
    if v_id is null
       or (v_m ->> 'origin') not in ('manual_received', 'manual_sent')
       or coalesce(btrim(v_m ->> 'content'), '') = ''
       or coalesce(btrim(v_m ->> 'author'), '') = '' then
      raise exception 'message invalide' using errcode = 'JVC12';
    end if;
    -- Réessai : déjà enregistré pour CE compte et CE contexte → ignoré.
    if exists (select 1 from public.context_messages where id = v_id) then
      if not exists (select 1 from public.context_messages
                      where id = v_id and user_id = p_user_id and context_id = p_context_id) then
        raise exception 'identifiant déjà utilisé' using errcode = 'JVC12';
      end if;
      continue;
    end if;
    insert into public.context_messages
      (id, context_id, user_id, message_order, source_order, author, content, kind,
       sent_at, sent_at_raw, origin, declared_proposition_id)
    values
      (v_id, p_context_id, p_user_id, v_suivant, null, btrim(v_m ->> 'author'),
       v_m ->> 'content', 'text', nullif(v_m ->> 'sent_at', '')::timestamp,
       coalesce(v_m ->> 'sent_at_raw', ''), v_m ->> 'origin',
       nullif(v_m ->> 'declared_proposition_id', ''));
    v_suivant := v_suivant + 1;
  end loop;

  return coalesce((
    select jsonb_agg(to_jsonb(m) - 'user_id' order by m.message_order)
      from public.context_messages m
     where m.context_id = p_context_id and m.user_id = p_user_id
       and m.id in (select (e ->> 'id')::uuid from jsonb_array_elements(p_messages) e)
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.ajouter_messages_contexte(uuid, uuid, jsonb) from public, anon, authenticated;
grant execute on function public.ajouter_messages_contexte(uuid, uuid, jsonb) to service_role;
