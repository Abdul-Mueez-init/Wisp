# Wisp Performance Fix Task List

**Status:** Locked working backlog  
**Scope:** Improve responsiveness and reduce lag without redesigning UI/UX or changing intended feature behavior.  
**Source baseline:** Current repository HEAD `3bfc98d` and connected Wisp Supabase project.  
**Delivery rule:** Every implementation step must provide complete replacement files for the affected screen, provider, repository, or feature—not isolated snippets.

## Non-negotiable engineering rules

1. A fix must not introduce a new error, race condition, subscription leak, data-loss path, or regression in another feature.
2. Existing features must continue to work with the same intended behavior. Performance improvements may reduce redundant work, but must not remove functionality.
3. The existing visual design and interaction model must remain intact. No new UI/UX direction is permitted unless explicitly requested.
4. All delivered code must be supplied as full file contents for the affected files.
5. The code must remain compatible with the current Flutter/Riverpod/Supabase architecture and build cleanly.
6. Changes must follow senior-level practices: scoped providers, deterministic lifecycle ownership, cancellation/disposal, bounded data access, stable widget identity, explicit error handling, and no unverified schema assumptions.
7. Each fix must be reviewed for feature preservation before the next fix begins.
8. No database schema or RLS change may be made silently. Any required migration must be identified separately and confirmed before implementation.

## Consolidated root-cause backlog

### P0 — Chat-list refresh amplification and N+1 query fan-out

**Current cause:** `myConversationSummariesProvider` listens to multiple broad realtime channels. Message inserts/updates, conversation-member inserts, and message-status updates all trigger a complete chat-list refresh. That refresh fetches all conversations and then performs multiple reads per conversation.

**Primary files:**

- `lib/features/chat/providers/conversation_provider.dart`
- `lib/features/chat/data/conversation_repository.dart`
- `lib/features/chat/screens/chat_list_screen.dart`

**Required outcome:** Preserve realtime reordering, unread badges, new-conversation visibility, and error/retry behavior while eliminating unnecessary full refreshes and reducing per-conversation request fan-out.

**Acceptance checks:** A message event in one conversation must not cause avoidable full-history reads for every conversation. The list must still reorder correctly, update unread counts correctly, and show newly created conversations.

### P0 — Unbounded unread-count and read-receipt database work

**Current cause:** Unread counting retrieves all incoming message rows and embedded status rows for each conversation, then counts in Dart. `markRead()` and related receipt methods also retrieve broad historical message/status ID sets.

**Primary files:**

- `lib/features/chat/data/conversation_repository.dart`
- `lib/features/chat/data/message_repository.dart`
- `lib/features/chat/screens/chat_detail_screen.dart`

**Required outcome:** Keep unread counts and delivered/read state semantically correct while ensuring normal list refreshes and chat entry do not repeatedly process complete conversation history.

**Acceptance checks:** Opening a chat marks the same messages as before; unread badges clear at the same functional points; empty conversations, missing status rows, direct chats, groups, and retry/error paths remain correct.

### P1 — Active-chat reactive rebuild pressure

**Current cause:** `ChatDetailScreen` watches several state sources in one build method. Message-window state, sending/uploading state, live-location state, conversation/profile state, group-member data, typing state, and presence state can cause rebuilds across a large subtree.

**Primary files:**

- `lib/features/chat/screens/chat_detail_screen.dart`
- `lib/features/chat/widgets/message_bubble.dart`
- `lib/features/chat/providers/message_provider.dart`
- relevant typing/presence providers

**Required outcome:** Keep the same screen layout and interactions while isolating changing subregions so message bubbles do not rebuild for unrelated header, typing, presence, send-state, or receipt changes.

**Acceptance checks:** Incoming messages, typing changes, presence changes, status-tick changes, send progress, and live-location changes update their intended UI without breaking scroll position or message ordering.

### P1 — Broad message-status realtime stream

**Current cause:** `watchMyVisibleStatuses()` streams all visible message-status rows allowed by RLS and filters/indexes them on the client. The current map-based status lookup is valid and must be preserved; the stale `O(messages × statuses)` diagnosis from the second report must not be reintroduced as an implementation assumption.

**Primary files:**

- `lib/features/chat/data/message_repository.dart`
- `lib/features/chat/providers/message_provider.dart`
- `lib/features/chat/widgets/message_bubble.dart`

**Required outcome:** Narrow status work to the relevant message window or otherwise prevent unrelated status events from causing active-chat work, without losing sent/delivered/read ticks.

**Acceptance checks:** Status ticks remain accurate for sent messages; incoming status updates remain visible where required; subscriptions are disposed when the relevant screen/provider is no longer used.

### P1 — Message-window rebuild and list-copy pressure

**Current cause:** `ChatMessagesController` copies and searches the in-memory message list on every realtime upsert, while `ChatDetailScreen` creates a reversed list during build. The current 30-message pagination and conversation-scoped realtime channel are valid and must be retained.

**Primary files:**

- `lib/features/chat/providers/message_provider.dart`
- `lib/features/chat/screens/chat_detail_screen.dart`

**Required outcome:** Preserve pagination, ordering, realtime insert/update/delete behavior, stable message keys, and scroll behavior while reducing avoidable list allocation and subtree rebuilds.

### P2 — Conditional per-message asynchronous/media work

**Current cause:** Media, video, document, contact, voice-note, and location message bubbles can create independent asynchronous provider work while a scrolling list is being built. This is conditional and is not the primary cause of plain-text chat lag.

**Primary files:**

- `lib/features/chat/widgets/message_bubble.dart`
- media/contact/voice/location providers and repositories

**Required outcome:** Preserve media rendering, signed URLs, document metadata, contact sharing, voice-note playback/transcription state, and location behavior while avoiding duplicate requests and unnecessary work for off-screen or unchanged bubbles.

### P2 — Rendering/compositing pressure from persistent glass navigation

**Current cause:** The persistent navigation shell uses a live `BackdropFilter` blur over the app body. This is a secondary device-dependent frame-time risk, not the main network/database bottleneck.

**Primary file:**

- `lib/core/routes/app_shell.dart`

**Required outcome:** Preserve the existing glass/pill appearance and navigation behavior while avoiding unnecessary rebuilds or compositing work. Any visual change must be minimal and explicitly justified.

### Excluded or already mitigated findings

The following are not current primary tasks unless new evidence appears:

- Per-message `O(messages × statuses)` scanning: current HEAD already uses an indexed status map and selected status ticks.
- One realtime presence subscription per displayed user: current HEAD uses one shared profile stream with an indexed map.
- Interactive `FlutterMap` inside every location bubble: current HEAD uses a static one-tile preview in the chat list; the full map remains available when opened.
- Nested shrink-wrapped chat list: current HEAD uses `CustomScrollView` and `SliverList`.
- Full-conversation message stream: current HEAD uses a bounded paginated message controller.
- WebRTC as a general chat-lag cause: only relevant to active calls, not ordinary chat/list responsiveness.

## Fix sequence

1. Establish a baseline and inspect the exact current files before modifying anything.
2. Fix chat-list refresh amplification and repository query fan-out.
3. Fix unbounded unread/read-receipt work while preserving semantics.
4. Isolate active-chat rebuild regions and preserve the existing message controller behavior.
5. Narrow or structurally isolate message-status stream work.
6. Optimize conditional media/location work only after core chat responsiveness is verified.
7. Review the glass navigation compositing cost last because it is device-dependent and secondary.
8. Run formatting, static analysis, tests, and a source-level regression review after each bounded change.
9. Deliver complete replacement files and a copy/paste order only after the changed files are internally consistent.

## Current working status

**Iteration 1 prepared:** The chat-list refresh/query path now has a bounded local implementation in the working copy and in `iteration_1_delivery/`. It batches direct-member profile lookup and unread-candidate lookup, keeps the latest-message query bounded per conversation, preserves existing summary sorting and AI/group semantics, and makes realtime refreshes single-flight so overlapping full refreshes cannot race or pile up.

**Files in iteration 1:**

- `lib/features/chat/data/conversation_repository.dart`
- `lib/features/chat/providers/conversation_provider.dart`

**Validation completed:** The repository diff passes `git diff --check`; the original files are backed up under `.performance_fix_backups/`. The sandbox does not have the Flutter SDK, so `flutter analyze`, compilation, and device regression validation must still be run in the user’s VS Code/Flutter environment before this iteration is considered fully accepted.

The backlog remains the governing task list for the implementation phase. The next implementation target after this iteration is active-chat reactive rebuild and status-stream pressure, but it must wait until iteration 1 builds cleanly and its unread, sorting, realtime, and new-conversation behavior are confirmed.
