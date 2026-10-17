-- =============================================================================
-- JARVIS — Phase 1 du stockage WhatsApp : contextes joints aux conversations
-- =============================================================================
-- Ajoute deux tables, sans toucher aux données existantes :
--   * conversation_contexts : une conversation WhatsApp jointe (pièce jointe)
--     à une conversation JARVIS, et au message JARVIS qui l'a introduite ;
--   * context_messages : les messages WhatsApp SÉLECTIONNÉS de ce contexte.
--
-- Une conversation JARVIS peut avoir plusieurs contextes (imports successifs).
-- Rien d'autre n'est stocké : ni ZIP, ni médias (seule leur trace textuelle),
-- ni copie dans public.messages, ni vecteurs.
--
-- Propriété : chaque ligne porte user_id ; des clés étrangères COMPOSITES
-- (x, user_id) garantissent qu'un contexte ne peut viser que la conversation
-- et le message de son propriétaire, et qu'un message WhatsApp appartient au
-- propriétaire de son contexte — y compris pour le backend (service_role,
-- qui contourne la RLS) : il devra seulement prendre user_id dans le JWT.
--
-- Écriture : backend uniquement (comme public.messages côté assistant).
-- Client (authenticated) : lecture et suppression de SES lignes (RLS).
--
-- Ré-exécutable (IF NOT EXISTS, politiques supprimées puis recréées).
-- Aucune instruction destructive sur les tables existantes.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 0. public.messages : (id, user_id) unique, cible de la FK composite
-- -----------------------------------------------------------------------------
-- Seul changement sur une table existante : contrainte UNIQUE supplémentaire.
-- id est déjà la clé primaire, donc (id, user_id) est déjà unique : aucune
-- ligne ne peut la violer, aucun comportement existant ne change (même
-- principe que conversations_id_user_id_key).
do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.messages'::regclass
       and conname  = 'messages_id_user_id_key'
  ) then
    alter table public.messages
      add constraint messages_id_user_id_key unique (id, user_id);
  end if;
end$$;

-- -----------------------------------------------------------------------------
-- 1. conversation_contexts
-- -----------------------------------------------------------------------------
create table if not exists public.conversation_contexts (
  id                  uuid primary key default gen_random_uuid(),
  user_id             uuid not null references public.users (id) on delete cascade,
  conversation_id     uuid not null,
  -- Message JARVIS (consigne) qui a introduit la pièce jointe ; null si ce
  -- message a été supprimé (le contexte reste attaché à sa conversation).
  message_id          uuid,
  source              text not null default 'whatsapp'
                        check (source in ('whatsapp')),
  -- Nom affiché du contact ou du groupe : jamais une clé (deux contacts
  -- peuvent porter le même nom).
  contact_name        text not null
                        check (char_length(contact_name) between 1 and 200),
  is_group            boolean not null default false,
  -- Participant confirmé par l'utilisateur comme étant lui-même.
  current_user_name   text
                        check (current_user_name is null
                               or char_length(current_user_name) <= 200),
  -- Participants détectés : tableau JSON de noms, ex. ["Tony Stark", "Jordi"].
  participants        jsonb not null default '[]'::jsonb
                        check (jsonb_typeof(participants) = 'array'),
  -- Période de la sélection, heure locale telle qu'écrite dans l'export
  -- (sans fuseau : l'export n'en donne pas). Null si aucune date lisible.
  period_start        timestamp without time zone,
  period_end          timestamp without time zone,
  -- Jour et mois indiscernables dans l'export : l'ordre retenu est supposé.
  dates_uncertain     boolean not null default false,
  -- Empreinte de l'export d'origine (calculée sur l'appareil) : servira à
  -- reconnaître un même export lors d'un import ultérieur.
  source_fingerprint  text
                        check (source_fingerprint is null
                               or char_length(source_fingerprint) <= 100),
  created_at          timestamptz not null default now(),

  unique (id, user_id),
  check (period_start is null or period_end is null or period_start <= period_end),
  -- La conversation doit appartenir au même utilisateur ; supprimée : ses
  -- contextes le sont aussi (comme ses messages).
  constraint conversation_contexts_conversation_fkey
    foreign key (conversation_id, user_id)
    references public.conversations (id, user_id) on delete cascade,
  -- Le message aussi ; supprimé : seul message_id devient null.
  constraint conversation_contexts_message_fkey
    foreign key (message_id, user_id)
    references public.messages (id, user_id) on delete set null (message_id)
);

-- Contextes d'une conversation, dans l'ordre des imports.
create index if not exists conversation_contexts_conversation_idx
  on public.conversation_contexts (conversation_id, created_at);
-- Contextes d'un utilisateur (RLS, suppression du compte).
create index if not exists conversation_contexts_user_idx
  on public.conversation_contexts (user_id, created_at desc);
-- Mise à null rapide quand un message JARVIS est supprimé.
create index if not exists conversation_contexts_message_idx
  on public.conversation_contexts (message_id)
  where message_id is not null;

-- -----------------------------------------------------------------------------
-- 2. context_messages
-- -----------------------------------------------------------------------------
create table if not exists public.context_messages (
  id              uuid primary key default gen_random_uuid(),
  context_id      uuid not null,
  -- Dénormalisé (comme public.messages) : RLS simple et rapide ; la FK
  -- composite impose le propriétaire du contexte.
  user_id         uuid not null,
  -- Position dans la sélection (0, 1, 2…) : l'ordre original.
  message_order   integer not null check (message_order >= 0),
  -- Position dans l'export d'origine (identifiant stable « m<ordre> »).
  source_order    integer check (source_order is null or source_order >= 0),
  -- Null pour un événement de WhatsApp (chiffrement, ajout au groupe…).
  author          text check (author is null or char_length(author) <= 200),
  content         text not null default ''
                    check (char_length(content) <= 65536),
  kind            text not null default 'text'
                    check (kind in ('text', 'media', 'deleted', 'system')),
  -- Type de média non importé (« image », « vocal »…) : une trace, jamais
  -- le fichier.
  media_type      text check (media_type is null or char_length(media_type) <= 40),
  -- Date et heure locales lues dans l'export, sans fuseau (aucune précision
  -- inventée) ; null si illisible. sent_at_raw garde le texte d'origine.
  sent_at         timestamp without time zone,
  sent_at_raw     text not null default ''
                    check (char_length(sent_at_raw) <= 100),
  created_at      timestamptz not null default now(),

  -- Un rang par contexte ; sert aussi d'index (lecture ordonnée, FK).
  constraint context_messages_order_key unique (context_id, message_order),
  constraint context_messages_context_fkey
    foreign key (context_id, user_id)
    references public.conversation_contexts (id, user_id) on delete cascade
);

-- -----------------------------------------------------------------------------
-- 3. Privilèges : écriture par le backend seulement
-- -----------------------------------------------------------------------------
revoke all on public.conversation_contexts, public.context_messages
  from public, anon, authenticated;
grant select, delete on public.conversation_contexts, public.context_messages
  to authenticated;
grant select, insert, update, delete on public.conversation_contexts,
  public.context_messages to service_role;

-- -----------------------------------------------------------------------------
-- 4. Row Level Security
-- -----------------------------------------------------------------------------
alter table public.conversation_contexts enable row level security;
alter table public.context_messages      enable row level security;

drop policy if exists "conversation_contexts_select_own" on public.conversation_contexts;
create policy "conversation_contexts_select_own" on public.conversation_contexts
  for select to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists "conversation_contexts_delete_own" on public.conversation_contexts;
create policy "conversation_contexts_delete_own" on public.conversation_contexts
  for delete to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists "context_messages_select_own" on public.context_messages;
create policy "context_messages_select_own" on public.context_messages
  for select to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists "context_messages_delete_own" on public.context_messages;
create policy "context_messages_delete_own" on public.context_messages
  for delete to authenticated
  using (user_id = (select auth.uid()));

-- -----------------------------------------------------------------------------
-- 5. Vue de consultation administrative (Dashboard uniquement)
-- -----------------------------------------------------------------------------
-- Le nombre de messages est calculé, jamais stocké (pas de compteur faux).
create or replace view admin.contextes_lisibles with (security_invoker = true) as
select x.id, x.user_id, u.display_name, u.email,
       x.conversation_id, c.title as conversation_title, x.message_id,
       x.source, x.contact_name, x.is_group, x.current_user_name,
       x.participants, x.period_start, x.period_end, x.dates_uncertain,
       (select count(*) from public.context_messages m where m.context_id = x.id)
         as messages_count,
       x.created_at
from public.conversation_contexts x
left join public.users u on u.id = x.user_id
left join public.conversations c on c.id = x.conversation_id;

revoke all on admin.contextes_lisibles from public, anon, authenticated, service_role;
