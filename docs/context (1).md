Wisp — Living Context

This file tracks current progress. Update it at the end of every session (see rules.md Rule 5). A new Claude/Copilot session should read this file first to know exactly what's built and what's next.

Status: Phases 0–10 built. QA/quality-check audit completed and all 🔴 findings from it fixed. Next: Phase 11 (Polish & Demo Prep), plus the remaining open items listed below.

## Completed (through the Profile-settings gap fix — narrated in real time, unchanged from before)
PRD.md, ERD.md, architecture.md, rules.md, plan.md, seed.sql, design.md — full doc set.
Phase 0-2: auth, onboarding, user search, 1-on-1 chat core.
Phase 3: group creation (creator becomes admin), admin-only add/remove members, group chat detail screen.
Phase 4: online/offline presence (Supabase Presence + profiles.is_online/last_seen_at), debounced typing indicators, last-seen labels.
Phase 5 (complete — 5a/5b/5c/5d/5e all shipped): images/video/document upload via private chat-media bucket + signed URLs; voice notes (record + just_audio, pseudo-waveform); contact sharing; location sharing (current + live, flutter_map/OSM, Nominatim reverse geocoding via LocationRepository, foreground-only live tracking, client-side expiry).
Phase 6 — Status/Stories: COMPLETE (6a, 6b, 6c all shipped). Story posting via public `stories` bucket, AppShell bottom-nav (Chats/Status/Calls/Settings), Chat List, Status List, and StoryViewerScreen (fullscreen viewer, progress bar, tap-through, story_views tracking, client-side auto-expiry).
Profile-settings gap fix (post-Phase-6, pre-Phase-7): ProfileRepository.updateProfile, UpdateProfileController, ProfileSettingsScreen (avatar picker, display name, preferred-language dropdown, sign-out) — closed the gap where preferred_language had no editable UI, which would have blocked Phase 7.

## Reconstruction note — Phases 7 through 10
The sessions that built Phases 7–10 did not update this file before ending (a Rule 5 miss —
flagging it plainly rather than pretending otherwise). The summary below was **not** narrated by
those sessions; it was reconstructed by directly reading the shipped code during a full QA/
quality-check audit, so treat it as verified-from-code rather than a first-hand session log.
Going forward, please keep this file updated in real time per Rule 5 — reconstructing it after
the fact is a poor substitute and is exactly how the bugs below went unnoticed for a while.

**Phase 7 — AI Feature 1: Real-Time Translation.** Shipped. The three decisions flagged as open
in this file's older "Next Up" section were resolved as: (1) direct-chats-only — group messages
are deliberately left untranslated, since `translated_content` is one column per row and can't
represent per-recipient translation; (2) background update-in-place — the message sends
immediately, translation is fire-and-forget and updates the row afterward, never blocking the
send; (3) one combined detect+translate AI call (single JSON response), not two. Lives in
`features/translation/`. `TranslationRepository.detectAndTranslate` routes through `AiConfig`
per Rule 8. Rendering (`message_bubble.dart`) correctly shows the translation only on the
receiver's side, never on the sender's own outgoing bubble.

**Phase 8 — AI Feature 2: Embedded AI Agent.** Shipped. Lives in `features/ai_agent/`.
`@wisp` mention detection is a whole-word, case-insensitive regex (`RegExp(r'@wisp\b', ...)`).
Context window pulls the most recent 20 messages descending, then reverses to oldest-first
before prompting. The DM-to-AI thread is implemented as an ordinary `type: 'direct'`
conversation with only one `conversation_members` row (no new `conversations.type` value,
no schema change) — the invariant holds because `_createDirect` always inserts both members
of a real human-to-human direct chat atomically, so a single-member direct conversation can
only ever be the reserved AI thread.

**Phase 9 — AI Feature 3: Voice Transcription + Action Extraction.** Shipped, with one incident
worth recording: `voice_transcription_repository.dart` was pushed to GitHub as a genuinely empty
(0-byte) file — the provider and `message_provider.dart` call sites referencing
`VoiceTranscriptionRepository`/`VoiceActionItem` were all present, but the class itself didn't
exist anywhere, so **the app did not compile**. This was caught during the QA audit, the missing
implementation was pushed from local (transcribe() via Gemini native audio input, no Groq
fallback since Groq's free tier has no comparable audio model; extractActions() as a second,
plain text-in/text-out call that does get the Groq fallback), and verified against every call
site (`message_provider.dart`, `message_repository.dart`, `voice_note_bubble.dart`'s
`{"items":[...]}` parsing) before being considered resolved.

**Phase 10 — Calling (Audio/Video).** Shipped, including a since-fixed crash: an earlier session
had `call_repository.dart` insert a `messages.type='call'` row with a `call_id` column that was
never in ERD.md/seed.sql, which threw an uncaught Postgres error on every call end/decline. The
code-side fix (removing `insertCallEventMessage`, removing `Message.callId`) was already in place
by the time of the QA audit; the audit additionally found the orphaned `call_id` column was still
sitting live in the DB even though nothing referenced it anymore, and dropped it via migration so
`messages` matches ERD.md exactly again. `calls_update_member` RLS confirmed live and correctly
scoped. `CallsTabScreen` confirmed wired into `app_shell.dart`. **Still not done by anyone: an
actual live device-to-device call.** No source-level review substitutes for this — it remains the
single most important open item for this phase.

## This session — QA/quality-check audit + fixes
Full audit against the live repo (`github.com/Abdul-Mueez-init/Wisp`) and the live Supabase
project, following `phase_QA_audit_handoff_doc.md`'s methodology (live schema/RLS via SQL, not
`seed.sql` assumptions; every third-party API call site checked against what's actually imported,
not memory). Findings and fixes:

- 🔴 **App didn't compile** — `voice_transcription_repository.dart` empty (see Phase 9 note
  above). Fixed: real file pushed from local, verified against every call site.
- 🔴 **`avatars` Storage bucket had zero RLS policies** — every avatar upload (onboarding +
  Settings) was silently denied. Fixed: added `avatars_bucket_select_all` (open read, bucket is
  public), `avatars_bucket_insert_own` and `avatars_bucket_update_own` (both scoped to the
  caller's own `{user_id}/` folder — `update` needed because `uploadAvatar` uses
  `FileOptions(upsert: true)`). Mirrors the existing `stories` bucket pattern exactly, nothing
  new invented.
- ⚠️ **Orphaned `messages.call_id` column** — leftover from the old Phase 10 bug, never
  referenced by code, never in ERD.md. Fixed: dropped via migration, confirmed the live column
  list now matches ERD.md exactly.
- 🔴 **Translation didn't match PRD.md §10 for English-source messages** — the shipped logic
  only skipped translation when the *detected* language matched the *target* language, so an
  English message would still get translated if the receiver's preferred language wasn't
  English. PRD.md §10 is unconditional: English source is never translated, period. Fixed in
  `translation_repository.dart` only — added the rule to the AI prompt itself, plus a
  code-level `isEnglishSource` check as a safety net so it doesn't depend on the model obeying
  the instruction. No other file needed changes since `message_bubble.dart`'s
  `showTranslation` already keyed off `translatedContent != null` alone.
- Two cosmetic analyzer warnings fixed at the same time (found by the project owner's own IDE,
  not part of the audit itself): an unused `material.dart` import in `app_router.dart`, and a
  redundant `!` in `voice_note_bubble.dart` (Dart's flow analysis already promoted the variable
  to non-null in that scope, so the assertion had no effect). Both zero-risk, no logic changed.
- `seed.sql` has been refined (separate deliverable) to match the live RLS exactly — it had
  drifted in three places (the Phase 3 `conversation_members` policy split,
  `message_status_select_sender`, `messages_update_own`) and never had a Storage RLS section at
  all despite `architecture.md` describing that shape in prose. `architecture.md`'s long-pending
  `features/groups/` amendment has also been folded into the canonical folder structure in this
  refined doc set, closing out an item that had been carried over as "outstanding" across
  multiple prior sessions.

## Deviations From Docs / Fixes Applied (carried over, still accurate)
Phase 3, bugfix: message_bubble.dart created (was referenced but never committed).
Phase 3, bugfix: conversation_members RLS members_admin_manage replaced with members_insert_creator_or_admin/members_update_admin/members_delete_admin. Confirmed live, now also reflected in seed.sql.
Phase 3, bugfix: added message_status_select_sender RLS policy. Now also reflected in seed.sql.
Phase 6 scope decisions, confirmed and shipped:
Stories visible to all authenticated users, not a contacts-only system (matches deployed stories_select_all RLS using (true)). PRD.md §8's "contacts" wording still doesn't reflect this — see Open Issues, still a decision for the project owner to make, not something changed silently here.
stories bucket: public, mirrors avatars.
AppShell built in 6b rather than deferred, per the Phase 6 handoff doc's recommendation.
No reply-to-story field, no sticker/text-overlay editor anywhere in Phase 6 — not backed by PRD.md/ERD.md, caption covers text-on-a-story.
Profile-settings gap fix decision, confirmed and shipped: username is not editable in Settings — deliberate scope line, not a limitation of the code.

## Open Issues
- PRD.md §8 "visible to contacts" wording vs. shipped "all users" — still open. This is a
  wording-vs-scope decision for the project owner, not something a QA pass should resolve
  unilaterally (rules.md Rule 1) — flagging again rather than silently editing PRD.md.
- Chat list is a FutureProvider, not live-realtime: it won't auto-reorder when a message arrives
  elsewhere in the app until refreshed/re-navigated. Flagged as a known limitation in
  conversation_provider.dart's doc comment, not treated as a bug.
- Typing-indicator staleness limitation from Phase 4 — unchanged, still acceptable for a demo.
- Avatar re-upload leaves the previous file orphaned in Storage when the file extension changes
  between uploads (path is {user_id}/avatar.{ext}). Pre-existing, not worth fixing for a
  portfolio/demo app; flagging in case free-tier Storage quota ever becomes a concern.
- Phase 10: no real device-to-device call has been placed yet by anyone (see above) — top
  priority before calling this feature demo-ready.
- Phase 11 (Polish & Demo Prep) has not been started.

## Notes for Next Session
design.md is the source of truth for all UI (Inter font, color tokens, spacing, component rules).
Work in batches of ~5-6 files (Rule 3).
Please update this file before ending a session (Rule 5) — the Phase 7–10 gap this session had to
reconstruct from code is exactly the failure mode Rule 5 exists to prevent.
