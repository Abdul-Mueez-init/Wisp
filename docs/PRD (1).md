# Wisp — Product Requirements Document

## 1. What is Wisp
Wisp is a WhatsApp-inspired realtime messaging app built as a Flutter portfolio piece, with three advanced AI features layered on top of a full-featured chat core. Goal: demonstrate realtime engineering (Supabase Realtime) AND applied AI product thinking in one app — a combination most freelance portfolios don't show.

This is a single-version build. There is no "v2" — every feature listed here is in final scope, sequenced across build phases in `plan.md`, but all shipped in one app.

## 2. Target audience (for the portfolio pitch)
Freelance/agency clients on Upwork/Fiverr evaluating Flutter + AI capability — this app is simultaneously a portfolio piece and a live sales demo for Quantix Labs' AI automation service.

## 3. Core Principles
- WhatsApp is the reference point for every UX decision unless explicitly stated otherwise.
- Zero-cost stack only: Supabase free tier + Gemini free tier (Groq as fallback). No paid SMS/Twilio.
- Realtime-first: presence, typing, message delivery, translation, and status must feel instant.

## 4. Authentication
- Email + Password via Supabase Auth (no phone/OTP — avoids Twilio/SMS provider cost).
- Onboarding requires creating a **unique username** (this is how users find and message each other — no phone-contact sync).
- Onboarding also sets: display name, avatar (optional), preferred language (defaults to English).

## 5. User Discovery
- Users search for others by username (not phone number).
- Starting a chat = search username → tap → open/create 1-on-1 conversation.

## 6. Chat Types
### 1-on-1 Chats
- Standard direct messaging.

### Group Chats
- Any user can create a group and add members (WhatsApp-style creation).
- **Only the group creator/admin can add/remove members and manage group settings** after creation.

## 7. Message Types (full WhatsApp parity)
- Text
- Images
- Videos
- Voice notes
- Documents (file upload/share)
- Contact sharing (share another Wisp user's profile as a message)
- Location sharing — **current location** (single pin) and **live location** (continuous updates for a set duration, via Supabase Realtime channel)

## 8. Presence & Status
- Online/offline presence (like WhatsApp's green dot), via Supabase Realtime presence channels.
- Typing indicators.
- Read receipts (sent/delivered/read states).
- **Status/Stories**: 24-hour disappearing photo/video stories, visible to contacts, WhatsApp-style.

## 9. Explicitly Out of Scope
- Disappearing/self-destructing messages (declined — adds complexity with no portfolio "wow" value).
- Phone number login / SMS OTP (cost barrier).

## 10. AI Features (the differentiator)

### AI Feature 1 — Real-Time Translation
- Every user sets a preferred language in profile settings (default: English, editable anytime).
- If a sender writes in English: message displays as-is, no translation shown.
- If a sender writes in any language other than English: the message is auto-translated to the receiver's preferred language, and **both original and translated text are shown** to the receiver.
- Powered by Gemini free tier (text-in/text-out call per message).

### AI Feature 2 — Embedded AI Agent
- Accessible two ways: (1) direct-message the AI like a regular contact, (2) `@mention` the AI inside any 1-on-1 or group chat.
- The agent has context of recent chat history (last ~15-20 messages) when responding, not just the single message it's mentioned in — this avoids shallow/hallucinated answers.
- Powered by Gemini free tier.

### AI Feature 3 — Voice Note Transcription + Action Extraction
- When a voice note is sent, it is transcribed automatically (Gemini's native audio input, no separate STT service needed).
- A second AI pass extracts action items / reminders from the transcript (e.g. "meet at 5pm tomorrow" → suggested action).
- Transcription + extracted actions are shown attached to the voice note message.

## 11. Calling (final build phase, full scope)
- Audio and video calls, 1-on-1 (group calls not required for v1 scope).
- WebRTC for peer connection, signaling via Supabase Realtime channels, free-tier TURN/STUN server (e.g. Metered.ca free tier) for NAT traversal.
- Built last because it depends on auth, chat, and realtime infrastructure already being stable — this is sequencing, not scope-cutting.
- Known limitation to disclose honestly to clients: free TURN server bandwidth is fine for demo/testing with a handful of devices, not stress-tested for high concurrent call volume.

## 12. Tech Stack Summary
- Frontend: Flutter
- State management: Riverpod
- Backend: Supabase (Postgres, Realtime, Storage, Auth)
- AI: Gemini API free tier (primary), Groq free tier (fallback)
- Calling: WebRTC + free TURN/STUN provider

## 13. Design
- UI/UX designed separately in Google Stitch by the founder; tracked in a separate `design.md` once ready. Not part of this initial doc batch.

## 14. App Name
**Wisp**
