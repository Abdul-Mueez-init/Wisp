# Wisp — Build Plan

Full scope, single version — phases below are build sequencing, not scope-cutting. Every phase ships as part of the same final app. Each phase is broken into session-sized chunks of roughly 5-6 files, per rules.md.

## Phase 0 — Project Setup
- Flutter project init, folder structure per architecture.md
- Supabase project setup, run seed.sql schema
- Riverpod + go_router + core packages installed
- ai_config.dart skeleton (Gemini + Groq clients, fallback logic stubbed)

## Phase 1 — Auth & Onboarding
- Email/password signup + login screens
- Onboarding flow: username creation (unique check), display name, avatar upload, preferred language (default English)
- `profiles` table wiring, auth state provider

## Phase 2 — User Discovery & 1-on-1 Chat Core
- Username search screen
- Start/open 1-on-1 conversation
- Chat detail screen: send/receive text messages, realtime message stream
- Message status (sent/delivered/read)

## Phase 3 — Group Chats
- Create group, add members (creator becomes admin)
- Admin-only member management (add/remove)
- Group chat detail screen (reuses chat core from Phase 2)

## Phase 4 — Presence & Typing
- Online/offline presence via Supabase Presence
- Typing indicators
- Last seen timestamps

## Phase 5 — Rich Message Types
- Images, videos, documents (Supabase Storage upload/download)
- Voice notes (recording, playback UI — transcription comes in Phase 7)
- Contact sharing (share a Wisp profile as a message)
- Location sharing: current location (pin) and live location (continuous updates)

## Phase 6 — Status/Stories
- Post photo/video story (24hr expiry)
- View stories from contacts, story_views tracking
- Auto-expiry handling

## Phase 7 — AI Feature 1: Real-Time Translation
- Language detection on message send
- Translation call via ai_config (Gemini) when non-English detected
- UI: show original + translated when applicable, per PRD logic
- Preferred language setting wired to translation target

## Phase 8 — AI Feature 2: Embedded AI Agent
- @mention detection in chat input
- DM-to-AI conversation (AI as a special "contact")
- Context window: pull last ~15-20 messages, send to Gemini, render response as AI message bubble

## Phase 9 — AI Feature 3: Voice Note Transcription + Action Extraction
- On voice note upload: transcription call (Gemini audio input)
- Second call: extract action items from transcript
- UI: display transcript + suggested actions attached to voice message

## Phase 10 — Calling (Audio/Video)
- WebRTC integration (flutter_webrtc)
- Signaling via Supabase Realtime channel
- TURN/STUN config (free-tier provider)
- Call UI: outgoing/incoming call screens, in-call controls (mute, camera toggle, end call)
- Call history logging (`calls` table)

## Phase 11 — Polish & Demo Prep
- Apply design.md (Google Stitch screens) across all screens if not already applied incrementally
- Empty states, error states, loading states audit
- Record demo video for portfolio/client pitch

## Session Handoff Reminder
At the end of every session: update context.md (Rule 5) before switching to a new Claude session or ending work for the day.
