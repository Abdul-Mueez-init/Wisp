-- Wisp — Supabase Schema & Seed
-- Matches ERD.md exactly. Do not modify without updating ERD.md first (see rules.md Rule 7).
--
-- Refined as part of the QA/quality-check pass: the CREATE TABLE statements below were
-- diffed column-by-column against the live Supabase project and match exactly (unchanged
-- from the previous version of this file). The RLS POLICIES section, however, had drifted
-- from what's actually deployed — several policies were added live across sessions without
-- this file being updated (a Rule 7 violation caught during the audit). That section has
-- been synced to match the live `pg_policies` output exactly. A STORAGE RLS section has
-- also been added — architecture.md always described the storage.objects RLS shape in
-- prose, but no session had ever captured it here as real SQL. Nothing below is invented;
-- every statement mirrors a policy that is actually live on the project today.

-- ============ EXTENSIONS ============
create extension if not exists "uuid-ossp";

-- ============ TABLES ============

create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique not null,
  display_name text,
  avatar_url text,
  preferred_language text not null default 'en',
  is_online boolean not null default false,
  last_seen_at timestamptz,
  created_at timestamptz not null default now()
);

create table conversations (
  id uuid primary key default uuid_generate_v4(),
  type text not null check (type in ('direct','group')),
  name text,
  avatar_url text,
  created_by uuid references profiles(id),
  created_at timestamptz not null default now()
);

create table conversation_members (
  id uuid primary key default uuid_generate_v4(),
  conversation_id uuid not null references conversations(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  role text not null default 'member' check (role in ('admin','member')),
  joined_at timestamptz not null default now(),
  unique (conversation_id, user_id)
);

create table messages (
  id uuid primary key default uuid_generate_v4(),
  conversation_id uuid not null references conversations(id) on delete cascade,
  sender_id uuid references profiles(id),
  is_ai_message boolean not null default false,
  type text not null check (type in ('text','image','video','voice','document','contact','location_current','location_live')),
  content text,
  media_url text,
  original_language text,
  translated_content text,
  shared_contact_id uuid references profiles(id),
  location_lat double precision,
  location_lng double precision,
  is_live_location boolean not null default false,
  live_location_expires_at timestamptz,
  voice_transcript text,
  voice_actions jsonb,
  created_at timestamptz not null default now()
);
-- Note: a `call_id` column briefly existed live (a leftover from an old Phase 10 bug
-- where a prior session wrote messages.type='call' rows with a call_id FK that was
-- never part of this schema). It has since been dropped from the live DB via migration
-- so the table matches the definition above exactly again — never re-add it without
-- updating ERD.md first, per Rule 7.

create table message_status (
  id uuid primary key default uuid_generate_v4(),
  message_id uuid not null references messages(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  status text not null default 'sent' check (status in ('sent','delivered','read')),
  updated_at timestamptz not null default now(),
  unique (message_id, user_id)
);

create table typing_status (
  conversation_id uuid not null references conversations(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  is_typing boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (conversation_id, user_id)
);

create table stories (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references profiles(id) on delete cascade,
  media_url text not null,
  caption text,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '24 hours')
);

create table story_views (
  id uuid primary key default uuid_generate_v4(),
  story_id uuid not null references stories(id) on delete cascade,
  viewer_id uuid not null references profiles(id) on delete cascade,
  viewed_at timestamptz not null default now(),
  unique (story_id, viewer_id)
);

create table calls (
  id uuid primary key default uuid_generate_v4(),
  conversation_id uuid not null references conversations(id) on delete cascade,
  caller_id uuid not null references profiles(id),
  type text not null check (type in ('audio','video')),
  status text not null default 'ringing' check (status in ('ringing','ongoing','ended','missed','declined')),
  started_at timestamptz,
  ended_at timestamptz
);

-- ============ ROW LEVEL SECURITY ============

alter table profiles enable row level security;
alter table conversations enable row level security;
alter table conversation_members enable row level security;
alter table messages enable row level security;
alter table message_status enable row level security;
alter table typing_status enable row level security;
alter table stories enable row level security;
alter table story_views enable row level security;
alter table calls enable row level security;

-- profiles: readable by all authenticated users (for username search), writable only by owner
create policy "profiles_select_all" on profiles for select using (true);
create policy "profiles_update_own" on profiles for update using (auth.uid() = id);
create policy "profiles_insert_own" on profiles for insert with check (auth.uid() = id);

-- conversation_members
-- Phase 3 bugfix (previously a single "members_admin_manage ... for all" policy, split into
-- three per-command policies live — this file now matches that live shape exactly):
create policy "members_select_own_conversations" on conversation_members for select
  using (exists (select 1 from conversation_members cm where cm.conversation_id = conversation_members.conversation_id and cm.user_id = auth.uid()));
create policy "members_insert_creator_or_admin" on conversation_members for insert
  with check (
    exists (select 1 from conversations c where c.id = conversation_members.conversation_id and c.created_by = auth.uid())
    or exists (select 1 from conversation_members cm where cm.conversation_id = conversation_members.conversation_id and cm.user_id = auth.uid() and cm.role = 'admin')
  );
create policy "members_update_admin" on conversation_members for update
  using (exists (select 1 from conversation_members cm where cm.conversation_id = conversation_members.conversation_id and cm.user_id = auth.uid() and cm.role = 'admin'));
create policy "members_delete_admin" on conversation_members for delete
  using (exists (select 1 from conversation_members cm where cm.conversation_id = conversation_members.conversation_id and cm.user_id = auth.uid() and cm.role = 'admin'));

-- conversations: visible only to members
create policy "conversations_select_member" on conversations for select
  using (exists (select 1 from conversation_members cm where cm.conversation_id = conversations.id and cm.user_id = auth.uid()));
create policy "conversations_insert_authenticated" on conversations for insert with check (auth.uid() is not null);

-- messages: visible/insertable only by conversation members
create policy "messages_select_member" on messages for select
  using (exists (select 1 from conversation_members cm where cm.conversation_id = messages.conversation_id and cm.user_id = auth.uid()));
create policy "messages_insert_member" on messages for insert
  with check (exists (select 1 from conversation_members cm where cm.conversation_id = messages.conversation_id and cm.user_id = auth.uid()));
-- Phase 7/9 addition (not in the previous version of this file): the sender needs to be
-- able to UPDATE their own message row after the fact, to write translated_content
-- (Phase 7) and voice_transcript/voice_actions (Phase 9) once the async AI call resolves.
create policy "messages_update_own" on messages for update
  using (auth.uid() = sender_id) with check (auth.uid() = sender_id);

-- message_status: visible/updatable only by the recipient themself
create policy "message_status_select_own" on message_status for select using (auth.uid() = user_id);
-- Phase 3 bugfix addition (not in the previous version of this file): a sender needs to
-- be able to see the delivery/read status of messages they sent, for read-receipt ticks.
create policy "message_status_select_sender" on message_status for select
  using (exists (select 1 from messages m where m.id = message_status.message_id and m.sender_id = auth.uid()));
create policy "message_status_update_own" on message_status for update using (auth.uid() = user_id);
create policy "message_status_insert_own" on message_status for insert with check (auth.uid() = user_id);

-- typing_status: visible to conversation members, writable by self
create policy "typing_select_member" on typing_status for select
  using (exists (select 1 from conversation_members cm where cm.conversation_id = typing_status.conversation_id and cm.user_id = auth.uid()));
create policy "typing_upsert_own" on typing_status for insert with check (auth.uid() = user_id);
create policy "typing_update_own" on typing_status for update using (auth.uid() = user_id);

-- stories: readable by all authenticated users, writable by owner only
create policy "stories_select_all" on stories for select using (true);
create policy "stories_insert_own" on stories for insert with check (auth.uid() = user_id);
create policy "stories_delete_own" on stories for delete using (auth.uid() = user_id);

-- story_views: viewer can insert their own view record; story owner can see who viewed
create policy "story_views_insert_own" on story_views for insert with check (auth.uid() = viewer_id);
create policy "story_views_select_owner_or_viewer" on story_views for select
  using (auth.uid() = viewer_id or exists (select 1 from stories s where s.id = story_views.story_id and s.user_id = auth.uid()));

-- calls: visible/insertable only by conversation members
create policy "calls_select_member" on calls for select
  using (exists (select 1 from conversation_members cm where cm.conversation_id = calls.conversation_id and cm.user_id = auth.uid()));
create policy "calls_insert_member" on calls for insert
  with check (exists (select 1 from conversation_members cm where cm.conversation_id = calls.conversation_id and cm.user_id = auth.uid()));
-- Phase 10 bugfix addition (not in the previous version of this file): both call
-- participants need to be able to UPDATE call status (answer/decline/end), not just insert.
create policy "calls_update_member" on calls for update
  using (exists (select 1 from conversation_members cm where cm.conversation_id = calls.conversation_id and cm.user_id = auth.uid()));

-- ============ STORAGE RLS (storage.objects) ============
-- Never previously captured in this file — architecture.md describes these in prose,
-- this is the actual live SQL shape for each of the three buckets it names.

-- chat-media (private, Phase 5): path convention {conversation_id}/{message_id}/{filename}
create policy "chat_media_select_member" on storage.objects for select
  using (bucket_id = 'chat-media' and exists (
    select 1 from conversation_members cm
    where cm.conversation_id = ((storage.foldername(objects.name))[1])::uuid
      and cm.user_id = auth.uid()
  ));
create policy "chat_media_insert_member" on storage.objects for insert
  with check (bucket_id = 'chat-media' and exists (
    select 1 from conversation_members cm
    where cm.conversation_id = ((storage.foldername(objects.name))[1])::uuid
      and cm.user_id = auth.uid()
  ));

-- stories (public, Phase 6): path convention {user_id}/{story_id}/{filename}
create policy "stories_bucket_select_all" on storage.objects for select
  using (bucket_id = 'stories');
create policy "stories_bucket_insert_own" on storage.objects for insert
  with check (bucket_id = 'stories' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "stories_bucket_delete_own" on storage.objects for delete
  using (bucket_id = 'stories' and (storage.foldername(name))[1] = auth.uid()::text);

-- avatars (public, Phase 1): path convention {user_id}/avatar.{ext}
-- Added during the QA/quality-check pass — this bucket had ZERO storage.objects policies
-- before, meaning every avatar upload (onboarding AND the Settings avatar editor) was
-- silently denied by RLS's default-deny. Mirrors the stories bucket pattern exactly.
create policy "avatars_bucket_select_all" on storage.objects for select
  using (bucket_id = 'avatars');
create policy "avatars_bucket_insert_own" on storage.objects for insert
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
-- update (not just insert) is required because ProfileRepository.uploadAvatar calls
-- uploadBinary with FileOptions(upsert: true), which performs an UPDATE when the path
-- already exists (e.g. re-uploading with the same file extension).
create policy "avatars_bucket_update_own" on storage.objects for update
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

-- ============ SEED DATA (test users for local dev/demo) ============
-- Note: auth.users rows must be created via Supabase Auth (signup flow), not directly here.
-- After creating 2-3 test accounts via signup, insert their matching profiles + a sample conversation, e.g.:
--
-- insert into profiles (id, username, display_name, preferred_language) values
--   ('<auth-user-id-1>', 'moeez', 'Moeez', 'en'),
--   ('<auth-user-id-2>', 'testuser2', 'Test User Two', 'es');
--
-- insert into conversations (id, type, created_by) values
--   ('11111111-1111-1111-1111-111111111111', 'direct', '<auth-user-id-1>');
--
-- insert into conversation_members (conversation_id, user_id, role) values
--   ('11111111-1111-1111-1111-111111111111', '<auth-user-id-1>', 'admin'),
--   ('11111111-1111-1111-1111-111111111111', '<auth-user-id-2>', 'member');
--
-- insert into messages (conversation_id, sender_id, type, content) values
--   ('11111111-1111-1111-1111-111111111111', '<auth-user-id-1>', 'text', 'Hola, como estas?');
--
-- This gives you a real 2-user conversation with a non-English message to test
-- translation (AI Feature 1) and read receipts immediately after setup.
