# Wisp Call System: Root Cause Analysis & Technical Diagnosis

This document provides the exact technical root cause analysis for all reported audio and video calling bugs in Wisp, based on codebase analysis, Supabase Realtime client inspections, and database replication audit.

---

## 1. Executive Summary of Bugs & Root Causes

| # | Bug Symptom | Pinpoint Root Cause | File & Line Reference |
|---|---|---|---|
| **1** | Call automatically cuts on Receiver when "Answer" is tapped (Phone B → Phone A & Video Calls) | **SDP Payload Nesting Mismatch:** Supabase Realtime wraps broadcast payloads in `{ "payload": { ... } }`. `webrtc_session.dart` tries to read `payload['sdp'] as String` directly from the outer envelope (which is `null`), throwing a runtime `TypeError`. The exception is caught by `answerCall()`, which calls `endCall()` and immediately cuts the call. | [`webrtc_session.dart:134-137`](file:///c:/development/wisp/lib/features/calls/data/webrtc_session.dart#L134-L137)<br>[`call_controller.dart:290-294`](file:///c:/development/wisp/lib/features/calls/providers/call_controller.dart#L290-L294) |
| **2** | Receiver shows "Connecting...", Sender shows "Calling..." forever (Phone A → Phone B) | **Signaling Race Condition & Dropped Ephemeral Broadcast:** Caller generates and broadcasts the WebRTC offer ~500ms after dialing. Callee only receives the DB event and joins the channel after 1–2.5s. Because Supabase Realtime Broadcast does not buffer or replay messages, the offer is lost. Callee awaits `signaling.onOffer.first` forever; Caller awaits `answer` forever. | [`call_controller.dart:136`](file:///c:/development/wisp/lib/features/calls/providers/call_controller.dart#L136)<br>[`call_controller.dart:264`](file:///c:/development/wisp/lib/features/calls/providers/call_controller.dart#L264) |
| **3** | No status transition from "Calling" → "Ringing" (Sender stuck on "Calling...") | **Fatal `UnsupportedError` on `const Map`:** `sendRingingAck()` passes `const {}`. Supabase's `realtime_client` attempts to mutate `payload['type'] = ...` in-place, which crashes on unmodifiable `const` maps. The `ringing_ack` packet is never transmitted. | [`signaling_repository.dart:104`](file:///c:/development/wisp/lib/features/calls/data/signaling_repository.dart#L104) |
| **4** | Remote Hangup / Cancel never reaches peer | **Fatal `UnsupportedError` on `const Map` in Hangup:** `sendHangup()` also passes `const {}`, crashing before the broadcast packet is sent over the wire. | [`signaling_repository.dart:102`](file:///c:/development/wisp/lib/features/calls/data/signaling_repository.dart#L102) |
| **5** | ICE Candidates never exchanged | **Candidate Payload Nesting Mismatch:** Same as Bug 1: candidate JSON is nested inside `payload['payload']`. `addRemoteIceCandidate` receives `null` for `candidate`, `sdpMid`, and `sdpMLineIndex`. | [`webrtc_session.dart:146-157`](file:///c:/development/wisp/lib/features/calls/data/webrtc_session.dart#L146-L157) |
| **6** | No ringing or beep sound audible | **Audio Focus Hijack & Earpiece Routing:** WebRTC mic acquisition requests `AUDIOFOCUS_GAIN` on Android, ducking/muting `just_audio`. Furthermore, audio calls run `setSpeaker(false)`, routing audio to the tiny earpiece speaker instead of the loud speakerphone. Sound player errors are silently swallowed with `catch (_)`. | [`webrtc_session.dart:70`](file:///c:/development/wisp/lib/features/calls/data/webrtc_session.dart#L70)<br>[`call_sound_player.dart:106-110`](file:///c:/development/wisp/lib/features/calls/data/call_sound_player.dart#L106-L110) |
| **7** | No call timer after answering | **Active View Never Mounted:** `_CallTimer` only mounts in `_ActiveCallView` (`CallPhase.active`). Because the handshake terminates or hangs before `active`, the timer is never displayed. | [`call_screen.dart:54-65`](file:///c:/development/wisp/lib/features/calls/screens/call_screen.dart#L54-L65) |
| **8** | Unreliable NAT traversal | **TCP-only TURN Configuration:** `.env` specifies a single `turns:...:443?transport=tcp` URL without UDP endpoints, preventing low-latency media transport on symmetric NATs/cellular connections. | [`.env:5`](file:///c:/development/wisp/.env#L5)<br>[`webrtc_config.dart:95-106`](file:///c:/development/wisp/lib/config/webrtc_config.dart#L95-L106) |

---

## 2. Detailed Technical Breakdown

### Bug 1: Fatal Payload Mismatch in Supabase Realtime Broadcast

#### The Code:
In `signaling_repository.dart`:
```dart
channel.onBroadcast(
  event: 'offer',
  callback: (payload) => _offerController.add(payload),
)
```
In `webrtc_session.dart`:
```dart
Future<void> setRemoteDescription(Map<String, dynamic> payload) async {
  final desc = RTCSessionDescription(
    payload['sdp'] as String,  // CRASH: null as String
    payload['type'] as String, // CRASH: 'broadcast' as type
  );
  await _pc!.setRemoteDescription(desc);
}
```

#### The Mechanism:
Supabase Realtime WebSocket sends messages in this structure:
```json
{
  "event": "offer",
  "type": "broadcast",
  "payload": {
    "sdp": "v=0\r\no=- 461173... IN IP4 0.0.0.0...",
    "type": "offer"
  }
}
```
When `onBroadcast` delivers `payload` to the callback, it delivers the **entire envelope**.
* `payload['sdp']` is `null` (it lives in `payload['payload']['sdp']`).
* `payload['type']` is `'broadcast'` (it lives in `payload['payload']['type']` as `'offer'`).
* Dart runtime throws: `type 'Null' is not a subtype of type 'String' in type cast`.
* In `call_controller.dart`:
```dart
try {
  ...
  final answer = await session.createAnswer(offer);
  ...
} catch (e) {
  state = state.copyWith(errorMessage: 'Could not answer the call: $e');
  await endCall(); // <--- CALL TERMINATED IMMEDIATELY
  return false;
}
```
* **Result:** The moment the receiver hits "Answer", `answerCall` crashes and runs `endCall()`, setting the call status to `missed` or `ended` and closing the screen.

---

### Bug 2: Signaling Race Condition (Ephemeral Broadcast Drop)

#### The Mechanism:
1. **Timing Asymmetry:**
   * Caller: `createCall()` -> inserts DB row -> joins channel `call:<callId>` -> acquires camera/mic -> creates SDP offer -> sends broadcast offer. Elapsed time: **~500ms–1s**.
   * Callee: Listens to `calls` table stream. Postgres replication + WebSocket delivery takes **1.5s–3s**. Callee's app receives the event, triggers `_handleIncomingCall()`, and begins `await signaling.join()`.
2. **Ephemeral Broadcast:**
   * Supabase Realtime Broadcast channels are pure ephemeral WebSockets without message queueing or persistence.
   * Because the Callee has not yet joined `call:<callId>` when the Caller sends the offer, the server drops the broadcast.
3. **The Deadlock:**
   * Caller sends the offer **only once**.
   * Callee taps "Accept", and executes:
     ```dart
     final offer = _pendingOffer ?? await signaling.onOffer.first;
     ```
   * Since `_pendingOffer` was never received, Callee awaits `signaling.onOffer.first` indefinitely.
   * Callee stays on `"Connecting..."`. Caller stays on `"Calling..."`.

---

### Bug 3 & 4: Fatal `UnsupportedError` on Immutable Maps in `sendRingingAck()` & `sendHangup()`

#### The Code:
In `signaling_repository.dart`:
```dart
Future<void> sendHangup() => _send('hangup', const {});
Future<void> sendRingingAck() => _send('ringing_ack', const {});
```
In Supabase's `realtime_client` package (`realtime_channel.dart` line 788):
```dart
Future<ChannelResponse> send({
  required RealtimeListenTypes type,
  String? event,
  required Map<String, dynamic> payload,
  Map<String, dynamic> opts = const {},
}) async {
  final completer = Completer<ChannelResponse>();

  payload['type'] = type.toType(); // <--- DIRECT MUTATION!
  if (event != null) {
    payload['event'] = event;      // <--- DIRECT MUTATION!
  }
```

#### The Mechanism:
* `const {}` is an immutable constant map in Dart.
* Mutating an immutable map in Dart throws: `Unsupported operation: Cannot modify unmodifiable map`.
* Both `sendRingingAck()` and `sendHangup()` fail synchronously in the background.
* Neither `ringing_ack` nor `hangup` is ever sent.
* Caller never receives `ringing_ack`, so `isRemoteRinging` never becomes `true`, and caller UI remains permanently on `"Calling..."`.

---

### Bug 5: ICE Candidates Extraction

In `webrtc_session.dart`:
```dart
Future<void> addRemoteIceCandidate(Map<String, dynamic> payload) async {
  final candidate = RTCIceCandidate(
    payload['candidate'] as String?,
    payload['sdpMid'] as String?,
    payload['sdpMLineIndex'] as int?,
  );
```
Because the payload is wrapped by Supabase Broadcast as `{ "event": "ice-candidate", "type": "broadcast", "payload": { "candidate": "...", "sdpMid": "...", "sdpMLineIndex": 0 } }`, all three values are extracted as `null`. No valid ICE candidates are ever added to `RTCPeerConnection`.

---

### Bug 6: Audio Focus Hijack & Earpiece Routing

1. **Audio Focus:**
   * Caller calls `session.init()`, which executes `navigator.mediaDevices.getUserMedia({'audio': true})`.
   * On Android, this requests `AUDIOFOCUS_GAIN` and switches `AudioManager` to `MODE_IN_COMMUNICATION`.
   * The `just_audio` player (running an in-memory WAV synthesizer) gets ducked or muted.
2. **Audio Output Routing:**
   * In `webrtc_session.dart`:
     ```dart
     await setSpeaker(isVideo);
     ```
   * For audio calls (`isVideo == false`), this runs `Helper.setSpeakerphoneOn(false)`, explicitly forcing audio to the **earpiece**. The user cannot hear any tone unless the phone is held directly to their ear.
3. **Sound Types:**
   * Caller needs a **Ringback / Dial tone** (repeating soft beep cadence).
   * Callee needs a **Loud Ringtone** routed to the **loud speakerphone** (`STREAM_RING` / speakerphone) so it is audible when the phone is on a table or in a pocket.

---

## 3. Action Plan for Fix Implementation (Next Phase)

When we begin implementation, we will execute the following concrete changes:

1. **Fix Broadcast Data Extraction:**
   * Update `signaling_repository.dart` to unwrap `payload['payload'] ?? payload` for `offer`, `answer`, and `ice-candidate`.
   * Ensure `setRemoteDescription` extracts both `sdp` and the correct `type` (`offer` or `answer`).

2. **Fix Mutable Map Bug:**
   * Replace all `const {}` with mutable `<String, dynamic>{}` in `sendRingingAck()` and `sendHangup()`.

3. **Solve the Signaling Race Condition (WhatsApp Flow):**
   * **Handshake Protocol:**
     * When Callee finishes `signaling.join()`, it immediately emits a `callee_ready` / `ringing_ack` event.
     * When Caller receives `callee_ready` / `ringing_ack`, Caller immediately sends the `offer` (or resends it).
     * In addition, Caller resends `offer` every 1.5s until `answer` is received or call ends.
     * Callee caches incoming `offer` in `_pendingOffer`. If Callee taps "Accept", it creates and returns `answer`.

4. **Synchronized Status Updates (WhatsApp Call State Sync):**
   * Caller starts in `Calling...`.
   * As soon as Callee joins channel and emits `ringing_ack`, Caller switches to `Ringing...`.
   * Both sides play appropriate tones.

5. **Audio Routing & Ringtones:**
   * Callee incoming call: Play loud ringtone over the loudspeaker/speakerphone.
   * Caller outgoing call: Play dial/ringback tone.
   * Fix audio focus attributes and provide proper looping audio sources.
   * Stop all tones the instant the call is accepted, declined, or ended.

6. **TURN / ICE Configuration:**
   * Update `WebrtcConfig` to configure both UDP and TCP TURN endpoints (`turn:global.relay.metered.ca:80`, `turn:global.relay.metered.ca:443`, `turns:global.relay.metered.ca:443?transport=tcp`).

7. **Call Timer & Teardown Synchronization:**
   * When `CallPhase.active` is reached on handshake completion, start timer.
   * When either party taps "End" or "Decline", ensure `hangup` broadcast cleanly tears down both sides in real time with duration displayed.
