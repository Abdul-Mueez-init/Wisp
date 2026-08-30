# Wisp — Architecture

This file defines the folder structure, state management pattern, and technical decisions. Every Claude session must follow this exactly. Do not introduce a different state management approach, folder layout, or package "because it's better" — if something here genuinely needs to change, it must be changed here first, explicitly, before any code follows the new pattern.

## Stack
- **Frontend**: Flutter
- **State management**: Riverpod (StreamProvider for realtime data, Notifier/AsyncNotifier for actions)
- **Backend**: Supabase — Postgres (data), Realtime (live sync), Storage (media files), Auth (email/password)
- **AI**: Gemini API free tier (primary) for translation, AI agent, voice transcription/action extraction. Groq free tier as fallback if Gemini rate-limits.
- **Calling**: WebRTC (flutter_webrtc package) + Supabase Realtime for signaling + free TURN/STUN provider (Metered.ca free tier or similar)

## Folder Structure
```
lib/
  core/
    constants/          # app-wide constants (colors, strings, durations)
    routes/              # go_router setup, route names
    theme/                # ThemeData, per design.md
    utils/                # helpers (date formatting, validators)
    errors/               # custom exceptions, failure types
  config/
    supabase_config.dart  # Supabase client init
    ai_config.dart         # Gemini/Groq client setup + fallback logic
  features/
    auth/
      data/                # repositories talking to Supabase Auth
      providers/           # Riverpod providers for auth state
      screens/             # login, signup, onboarding (username setup)
      widgets/
    chat/
      data/                # message/conversation repositories
      providers/           # StreamProviders for messages, typing, presence
      screens/              # chat list, chat detail, group creation
      widgets/               # message bubble, input bar, typing indicator
    groups/
      data/                 # group creation, membership add/remove
      providers/             # CreateGroupController, groupMembersProvider, etc.
      screens/                # group creation, group member management
    contacts/
      data/
      providers/
      screens/               # username search / user discovery
      widgets/
    stories/
      data/
      providers/
      screens/
      widgets/
    calls/
      data/                 # WebRTC signaling logic
      providers/
      screens/
      widgets/
    ai_agent/
      data/                 # Gemini calls for embedded agent
      providers/
      widgets/                # AI message bubble variant
    translation/
      data/                 # Gemini translation calls
      providers/
    voice_notes/
      data/                 # transcription + action extraction calls
      providers/
      widgets/
    profile/
      data/
      providers/
      screens/               # profile settings, preferred language
  models/                     # shared data models (Message, Conversation, Profile, Story, Call)
  widgets/                    # truly global/shared widgets only (buttons, loaders)
  main.dart
```

**`features/groups/` vs `features/chat/` split** (formerly a standalone amendment note, folded into
the canonical structure above as of the QA/refinement pass — no behavior changed, this only brings
the doc in line with what Phase 3 actually shipped): group creation and membership management
(`group_repository.dart`, `group_provider.dart`, the creation/member screens) is a meaningfully
distinct domain from the messaging domain `chat/` owns. New group-membership/creation logic belongs
in `features/groups/`; any new message-rendering/sending logic (including group-message-specific
rendering) belongs in `features/chat/`. The group chat *detail* screen still correctly reuses
`chat/screens/chat_detail_screen.dart` per `plan.md` — that's the part of "reuses chat core" that
actually mattered; `groups/` never duplicated it.

## State Management Rules
- Realtime data (messages, typing, presence, call state) → `StreamProvider` wired directly to a Supabase Realtime stream.
- One-off actions (send message, create group, update profile) → `AsyncNotifier`/`Notifier` classes.
- No `setState` for anything that touches shared/app state — local ephemeral UI state (e.g. a text field's focus) is the only acceptable `StatefulWidget` use case.
- Providers live in each feature's `providers/` folder — do not create a single giant global providers file.

## Storage Buckets
- **`avatars`** — public bucket (Phase 1). Path: `{user_id}/avatar.{ext}`. Resolved via `getPublicUrl`.
  Storage RLS on `storage.objects`: open `select` (matches the bucket's public-read intent), `insert`
  and `update` both restricted to the caller's own `{user_id}/` prefix (`update` is required because
  `ProfileRepository.uploadAvatar` uses `FileOptions(upsert: true)`, which performs an UPDATE when the
  same path already exists — e.g. a re-upload with an unchanged file extension). No `delete` policy —
  nothing in the app calls storage delete on this bucket (see the avatar-re-upload orphaning note in
  `context.md`; that's a known, accepted limitation, not something this RLS shape should paper over).
- **`chat-media`** — private bucket (Phase 5). Path convention: `{conversation_id}/{message_id}/{filename}`.
  Storage RLS on `storage.objects` mirrors the `messages` table RLS shape: a user may
  select/insert an object only if they're a `conversation_members` row for the
  conversation encoded in the object's first path segment. Because the bucket is
  private, callers never call `getPublicUrl` — every read goes through a short-lived
  `createSignedUrl` call (see `MediaRepository`). Used for `image`/`video`/`voice`/`document`
  message types.
- **Client-side upload caps** (free-tier Supabase Storage, not a hard server limit — just
  sane guardrails so one upload can't eat the free quota): images 8MB, video 50MB,
  documents 25MB.
- **`stories`** — public bucket (Phase 6). Path convention: `{user_id}/{story_id}/{filename}`.
  Mirrors `avatars`' pattern exactly (plain `getPublicUrl`, no signed-URL step) — deliberate,
  since `stories` table RLS (`stories_select_all`, `using (true)`) already makes every active
  story readable by any authenticated user, so a private+signed-URL bucket (`chat-media`'s
  pattern) would add complexity for no actual privacy benefit. Storage RLS on
  `storage.objects`: public select; insert/delete restricted to the caller's own
  `{user_id}/` prefix.

## Data Flow Pattern
1. UI widget watches a Riverpod provider.
2. Provider (in `data/`) talks to Supabase client or Gemini/Groq client.
3. Realtime changes flow back through the stream automatically — no manual polling/refresh.

## AI Integration Pattern
- All AI calls go through `config/ai_config.dart`, which tries Gemini first, falls back to Groq on rate-limit/error. Feature code never calls Gemini/Groq SDKs directly — always through this shared client wrapper.
- Translation: triggered on message send if detected language != English; result stored in `messages.translated_content` per ERD.md. English-source text is never translated regardless of the receiver's preferred language (PRD.md §10) — enforced both in the AI prompt and as a code-level check in `TranslationRepository`, not left to model compliance alone. Scoped to direct (1-on-1) chats only — `translated_content` is a single column per row, which can't cleanly represent "translated differently per recipient" for a group, so group messages are left untranslated. Runs as a background update-in-place after the message row is inserted (fire-and-forget, doesn't block the send) — one combined detect+translate AI call per message (single JSON-shaped response), not two separate calls.
- AI agent: triggered on @mention detection (`@wisp`, whole-word, case-insensitive) or DM-to-AI conversation; pulls last ~15-20 messages from the conversation as context per PRD.md, oldest-first.
- Voice notes: on upload, transcription call via Gemini's native audio input (no Groq fallback — Groq's free tier has no comparable audio model), then a second call for action extraction (this one does get the Groq fallback, since it's plain text-in/text-out); both results stored on the `messages` row per ERD.md.

## Coding Conventions
- File naming: `snake_case.dart`
- Class naming: `PascalCase`
- One widget per file for any non-trivial widget (avoid mega-files with multiple widget classes)
- No business logic inside widgets — widgets read providers and render; logic lives in providers/repositories

## Error Handling
- All Supabase/AI calls wrapped in try/catch, surfaced through a shared `Failure`/`Result` pattern (defined in `core/errors/`) — no raw exceptions bubbling to UI.

## Out of Scope for This File
- Visual design tokens (colors, typography, spacing) — these live in `design.md`, sourced from Google Stitch screens.
