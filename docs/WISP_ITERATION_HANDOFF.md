# Wisp Performance Fix — Handoff Document

**Purpose of this document:** This is a handoff for whichever AI assistant picks up this work next. It states what was actually found, what has actually been done, what has not, and what must be verified before trusting anything below — including this document itself.

**Project:** Wisp — Flutter/Riverpod/Supabase mobile messaging app
**Repository:** `Abdul-Mueez-init/Wisp` (public on GitHub)
**Baseline commit at time of writing:** `9815136f2aecf919b673ee7640048ecd130cf4e8` ("app performance work")
**Supabase project:** `Wisp`, project ref `pbrhczmloobsclynbvlj`, region `ap-northeast-1`
**Handoff prepared:** 5 September 2026

---

## 0. Read this before doing anything else

This project has already been burned twice by trusting documentation instead of code:

1. A separate performance report (produced without live repo access, working from old pasted code snapshots) flagged four "Critical/High" issues that turned out to already be fixed in the current codebase — a per-message `O(messages × statuses)` status scan, a read-receipt sync that fired on every stream emission, an interactive map widget inside every location bubble, and one presence subscription per displayed user. All four were confirmed fixed by reading the actual live code.
2. The task list this handoff is based on (produced by Manus AI, referenced throughout) contains at least one internal arithmetic error in its own code comments (see §3, Phase 1) — the code is correct, the comment describing it is off by one.

**Rule for whoever works on this next:** Before making any claim about what state the code is in, clone the repo fresh and read the actual file. Do not infer current state from a task list, a prior AI's summary, or a code comment. `git log` on the actual repo, not the stated intention, is ground truth.

---

## 1. Where the code actually stands right now (verified, not assumed)

- **Live GitHub HEAD is `3bfc98d`.** This is the pre-fix baseline. Verified by a fresh clone immediately before writing this document.
- **Iteration 1's two files have NOT been committed or pushed.** They exist only as text the user pasted into their local project copy:
  - `lib/features/chat/data/conversation_repository.dart`
  - `lib/features/chat/providers/conversation_provider.dart`
- If you (the next AI) are given repo access and see `3bfc98d` as HEAD, **do not assume iteration 1 hasn't happened** — ask the user whether their local working copy already has it pasted in, since git will not show it.
- **Recommended immediate action, before any further code changes:** get iteration 1 committed and pushed so `git log` becomes trustworthy again. Every fix from this point on should be delivered as a diff against a known, pushed commit — not against "whatever the user has locally right now."

---

## 2. Manus AI's non-negotiable engineering rules (carry these forward unchanged)

These governed iteration 1 and must continue to govern every subsequent fix:

1. A fix must not introduce a new error, race condition, subscription leak, data-loss path, or regression in another feature.
2. Existing features must continue to work with the same intended behavior. Performance improvements may reduce redundant work, but must not remove functionality.
3. The existing visual design and interaction model must remain intact. No new UI/UX direction unless explicitly requested.
4. All delivered code must be supplied as **full file contents** for the affected files — not isolated snippets/diffs.
5. Code must remain compatible with the current Flutter/Riverpod/Supabase architecture and build cleanly.
6. Senior-level practices required: scoped providers, deterministic lifecycle ownership, cancellation/disposal, bounded data access, stable widget identity, explicit error handling, no unverified schema assumptions.
7. Each fix must be reviewed for feature preservation before the next fix begins.
8. No database schema or RLS change may be made silently. Any required migration must be identified separately and confirmed before implementation.

---

## 3. Root-cause backlog, converted into phases, with real status

The original diagnosis (independently verified against live repo code and the live Supabase project) found the app's lag is architectural: realtime events trigger broad refetches and unbounded scans, which cascade into more realtime events and rebuilds. Below is that backlog reorganized into sequential phases, each marked with actual status.

### Phase 1 (was P0) — Chat-list refresh amplification and N+1 query fan-out
**Status: DONE — verified by direct diff against baseline. Not yet pushed to git (see §1).**

- **Cause:** `myConversationSummariesProvider` re-runs `fetchMyConversationSummaries()` on any relevant realtime event (message insert/update, new membership, own read-receipt update), debounced 300ms. That refresh used to run 3 queries **per conversation** (other-member lookup, last-message lookup, unread-count) via `Future.wait`.
- **What iteration 1 actually changed (confirmed via diff against `3bfc98d`):**
  - `conversation_repository.dart`: the other-member lookup and the unread-count lookup are now each **one batched query across all conversations**, instead of one query per conversation. The last-message lookup remains one query per conversation (PostgREST cannot express "latest row per group" without an RPC — this is a real constraint, not an oversight).
  - Net effect: requests per full chat-list refresh go from roughly `1 + 3C` to `3 + C`, where `C` = conversation count. (Note: the code's own doc comment says "`2 + C`" — that's an arithmetic mistake in the comment; the actual query count is `3 + C`. The code itself is correct.)
  - `conversation_provider.dart`: added a single-flight guard (`refreshInFlight` / `refreshQueued`) around the debounced `refresh()` call, so an overlapping refresh queues instead of racing, then re-fires once the in-flight one completes. Dispose path is clean.
- **Verified correct for edge cases:** AI-DM conversation (single-member direct chat) still resolves `otherProfile: null` correctly. Group conversations still discard the batched profile lookup correctly (`otherProfile` only used when `conversation.isDirect`). Sorting and empty-list handling unchanged.
- **Known minor cleanup, not blocking:** the batched profile query still pulls member rows for group conversations even though the result is discarded for non-direct conversations — wasted rows, not a bug. Low priority.

### Phase 2 (was P0) — Unbounded unread-count and read-receipt database work
**Status: NOT STARTED. This is the phase that got skipped when "iteration 2" was proposed — see §4.**

- **Cause:** Unread-count calculation and read-receipt marking pull **every incoming message in a conversation's full history** (with all related status rows) and process client-side in Dart. There is no pagination, limit, or time window.
- **Confirmed still true after iteration 1:** The unread-count query in `conversation_repository.dart` is now a single *batched* query across conversations (see Phase 1), but it is still an **unbounded** query — it fetches the complete incoming-message history for every conversation, every single chat-list refresh. Iteration 1 reduced round-trip *count*, not data *volume*.
- **Confirmed completely untouched:** `lib/features/chat/data/message_repository.dart` — `markDelivered()`, `markRead()`, `_incomingMessageIds()`, `_trackedMessageIds()` are byte-for-byte unchanged from baseline. Opening a chat or marking it read still fetches every incoming message ID for that conversation's entire history before doing anything.
- **Primary files:** `lib/features/chat/data/conversation_repository.dart`, `lib/features/chat/data/message_repository.dart`, `lib/features/chat/screens/chat_detail_screen.dart`
- **Required outcome (unchanged from original plan):** Keep unread counts and delivered/read state semantically correct while ensuring normal list refreshes and chat entry do not repeatedly process complete conversation history.
- **Acceptance checks:** Opening a chat marks the same messages as before; unread badges clear at the same functional points; empty conversations, missing status rows, direct chats, groups, and retry/error paths remain correct.

### Phase 3 (was P1) — Active-chat reactive rebuild pressure
**Status: NOT STARTED.**

- **Cause:** `ChatDetailScreen` watches many state sources (message-window state, send/upload state, live-location state, conversation/profile data, group members, typing, presence) in one build method, causing broad rebuilds across the screen for small, localized changes.
- **Primary files:** `lib/features/chat/screens/chat_detail_screen.dart`, `lib/features/chat/widgets/message_bubble.dart`, `lib/features/chat/providers/message_provider.dart`, relevant typing/presence providers.
- **Required outcome:** Same layout and interactions, but changing subregions isolated so message bubbles don't rebuild for unrelated header/typing/presence/send-state/receipt changes.

### Phase 4 (was P1) — Broad message-status realtime stream
**Status: NOT STARTED.**

- **Cause:** `watchMyVisibleStatuses()` streams all visible `message_status` rows allowed by RLS and indexes them client-side. **Important:** the current map-based lookup (`messageStatusByIdProvider` + `.select()`) is already correct and must be preserved — do not reintroduce the stale "O(messages × statuses) per-render scan" diagnosis, which was already fixed prior to this backlog and confirmed by direct code inspection.
- **Primary files:** `lib/features/chat/data/message_repository.dart`, `lib/features/chat/providers/message_provider.dart`, `lib/features/chat/widgets/message_bubble.dart`
- **Required outcome:** Narrow status work to the relevant message window, or otherwise prevent unrelated status events from causing active-chat work, without losing sent/delivered/read ticks.

**Manus's proposed "iteration 2" combines Phase 3 and Phase 4** ("isolate active-chat reactive rebuilds and reduce message-status stream pressure while preserving message ordering, scrolling, typing/presence, read receipts, media, and the existing UI"). See §4 for why this is a sequencing concern.

### Phase 5 (was P1) — Message-window rebuild and list-copy pressure
**Status: NOT STARTED.**

- **Cause:** `ChatMessagesController` copies and searches the in-memory message list on every realtime upsert; `ChatDetailScreen` builds a reversed copy of the list on every build. **Important:** the current 30-message pagination and conversation-scoped realtime channel are already correct and must be retained — do not reintroduce the stale "full-conversation stream" diagnosis.
- **Primary files:** `lib/features/chat/providers/message_provider.dart`, `lib/features/chat/screens/chat_detail_screen.dart`
- **Required outcome:** Preserve pagination, ordering, realtime insert/update/delete behavior, stable message keys, and scroll behavior while reducing avoidable list allocation and subtree rebuilds.

### Phase 6 (was P2) — Conditional per-message asynchronous/media work
**Status: NOT STARTED. Secondary — only matters when media/contact/location messages are present.**

- **Cause:** Media, document, contact, voice-note, and location bubbles can create independent async provider work while the scrolling list builds.
- **Primary files:** `lib/features/chat/widgets/message_bubble.dart`, media/contact/voice/location providers and repositories.
- **Required outcome:** Preserve all existing media/contact/voice/location behavior while avoiding duplicate requests and unnecessary work for off-screen or unchanged bubbles.

### Phase 7 (was P2) — Rendering/compositing pressure from persistent glass navigation
**Status: NOT STARTED. Secondary, device-dependent — do last.**

- **Cause:** The persistent nav shell uses a live `BackdropFilter` blur (`ImageFilter.blur(sigmaX: 12, sigmaY: 12)`) over the app body — a GPU/compositing cost, not a network/database one.
- **Primary file:** `lib/core/routes/app_shell.dart`
- **Required outcome:** Preserve the existing glass/pill appearance and navigation behavior while avoiding unnecessary rebuilds or compositing work. Any visual change must be minimal and explicitly justified.

### Already mitigated — confirmed fixed prior to this backlog, do not re-flag as new findings
Confirmed by direct code inspection, not by trusting comments:
- Per-message `O(messages × statuses)` scanning — replaced by an indexed status map with `.select()`-scoped rebuilds.
- One realtime presence subscription per displayed user — replaced by a single shared `allProfilesStreamProvider` with an indexed map.
- Interactive `FlutterMap`/`TileLayer`/`MarkerLayer` inside every location bubble — replaced by a static one-tile `Image.network` preview in the scrolling list; the full interactive map still exists in the dedicated viewer screen.
- Nested shrink-wrapped chat list (`ListView` inside `ListView` with `shrinkWrap`/`NeverScrollableScrollPhysics`) — current code uses `CustomScrollView`/`SliverList`.
- Full-conversation unbounded message stream — current code uses a bounded, paginated message controller with a conversation-scoped realtime channel.
- WebRTC calling issues — a separate, unrelated active workstream (caller stuck on "Calling...", no audio connection, etc.). Not a general chat-lag cause; do not conflate with this backlog.

---

## 4. The sequencing issue — flag this explicitly to whoever works on this next

Manus's own task list states a fix sequence: (1) baseline → (2) chat-list fan-out → **(3) unbounded unread/read-receipt work** → (4) active-chat rebuilds → (5) status-stream narrowing → (6) media/location → (7) glass nav.

Iteration 1 completed step 2 only. The "iteration 2" scope Manus proposed next — active-chat rebuilds + status-stream narrowing — is steps 4 and 5. **Step 3 (Phase 2 above) is skipped entirely** in that proposal, despite being ranked at the same "Critical" severity as the phase that was just fixed.

This matters concretely: after iteration 1, the chat *list* is cheaper to refresh, but opening an individual chat or marking it read still performs an unbounded full-history scan (Phase 2, untouched). If Phase 3/4 work proceeds before Phase 2, the most severity-critical unresolved item will remain unresolved indefinitely unless someone deliberately loops back to it.

**This decision was left open with the user at handoff time — it was not resolved.** The next AI should ask the user directly rather than assume:
- Do Phase 2 (the skipped unbounded unread/read-receipt fix) first, matching Manus's own stated sequence, or
- Proceed with Phase 3/4 ("iteration 2" as Manus framed it) and consciously defer Phase 2, or
- Some combination.

---

## 5. How to verify any of this yourself before proceeding

- Clone fresh: `git clone https://github.com/Abdul-Mueez-init/Wisp.git` — check `git log -1` against the baseline commit stated in §0 (or whatever is current by the time you read this).
- The two iteration-1 files, as actually pasted by the user (not the git-tracked version, since they aren't pushed), should be obtained directly from the user if you need to confirm current local state.
- Supabase project ref: `pbrhczmloobsclynbvlj`. At time of writing: 9 conversations, 47 messages, 43 `message_status` rows, `message_status` table has two permissive SELECT policies (`message_status_select_own`, `message_status_select_sender`) flagged by the Supabase performance advisor, several unused indexes flagged (informational, not the primary bottleneck), realtime publication includes `calls`, `message_status`, `messages`, `profiles`, `typing_status`.
- Do not treat any number, claim, or "already fixed" status in this document as permanent — table sizes, row counts, and code state will have moved on by the time you read this. Re-verify against the live repo and live Supabase project before acting.
