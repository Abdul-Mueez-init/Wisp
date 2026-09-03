// lib/features/calls/providers/call_session_state.dart
import '../../../models/call.dart';

/// Local UI-facing phases for the *current device's* view of a call.
/// Distinct from `Call.status` (the persisted, shared history state) —
/// e.g. both caller and callee pass through `connecting` on their own
/// schedule even though the shared `Call.status` only ever sees
/// ringing/ongoing/ended/missed/declined.
enum CallPhase {
  idle,
  outgoingRinging,
  incomingRinging,
  connecting,
  active,
  ended,
}

/// Immutable snapshot of the current call session on this device.
/// Deliberately does not hold the `WebrtcSession`/`SignalingRepository`
/// instances themselves (those are private mutable fields on
/// `CallController`, not state) — this is what screens watch/render.
class CallSessionState {
  const CallSessionState({
    this.phase = CallPhase.idle,
    this.call,
    this.otherUserId,
    this.isVideo = false,
    this.isMuted = false,
    this.isCameraOff = false,
    this.isSpeakerOn = false,
    this.isRemoteRinging = false,
    this.callConnectedAt,
    this.errorMessage,
  });

  final CallPhase phase;
  final Call? call;
  final String? otherUserId; // the peer, for profile lookup/display
  final bool isVideo;
  final bool isMuted;
  final bool isCameraOff;

  /// Ear-speaker (false) vs phone-speaker (true). Video calls default to
  /// true, audio calls to false — see `WebrtcSession.initLocalMedia`.
  final bool isSpeakerOn;

  /// True once the callee's device has actually joined the signaling
  /// channel (app alive, online) and sent back a `ringing_ack` — this is
  /// what flips the caller's own screen from "Calling…" to "Ringing…",
  /// mirroring WhatsApp. Only meaningful on the caller side; the callee
  /// never reads it.
  final bool isRemoteRinging;

  /// Wall-clock moment the call reached `active` on THIS device — set
  /// once, from either the caller's `onAnswer` handler or the callee's
  /// own `answerCall()` success path. Purely a UI concern (the in-call
  /// duration timer); never persisted, unlike `Call.startedAt`/`endedAt`.
  final DateTime? callConnectedAt;

  final String? errorMessage;

  bool get isIdle => phase == CallPhase.idle;

  static const idle = CallSessionState();

  CallSessionState copyWith({
    CallPhase? phase,
    Call? call,
    String? otherUserId,
    bool? isVideo,
    bool? isMuted,
    bool? isCameraOff,
    bool? isSpeakerOn,
    bool? isRemoteRinging,
    DateTime? callConnectedAt,
    String? errorMessage,
  }) {
    return CallSessionState(
      phase: phase ?? this.phase,
      call: call ?? this.call,
      otherUserId: otherUserId ?? this.otherUserId,
      isVideo: isVideo ?? this.isVideo,
      isMuted: isMuted ?? this.isMuted,
      isCameraOff: isCameraOff ?? this.isCameraOff,
      isSpeakerOn: isSpeakerOn ?? this.isSpeakerOn,
      isRemoteRinging: isRemoteRinging ?? this.isRemoteRinging,
      callConnectedAt: callConnectedAt ?? this.callConnectedAt,
      errorMessage: errorMessage,
    );
  }
}
