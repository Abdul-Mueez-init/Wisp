// lib/features/calls/providers/call_controller.dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show RTCPeerConnectionState;

import '../../../config/supabase_config.dart';
import '../../../models/call.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/call_sound_player.dart';
import '../data/signaling_repository.dart';
import '../data/webrtc_session.dart';
import 'call_provider.dart';
import 'call_session_state.dart';

/// Owns the whole call lifecycle end to end: place a call, detect and
/// answer/decline an incoming one, and hang up — wiring
/// [SignalingRepository] (SDP/ICE transport), [WebrtcSession] (the
/// peer connection itself), [CallSoundPlayer] (ring/dial tone), and
/// [CallRepository] (persisted ringing/ongoing/ended/missed/declined
/// history) together. Same `Notifier<State>` shape as
/// `LiveLocationController` in features/location — a single long-lived
/// controller for a lifecycle with an explicit start/active/stop shape,
/// not a one-shot `AsyncNotifier` action.
///
/// Only one call is ever active on this device at a time — matches
/// PRD.md §11's 1-on-1-only scope and avoids juggling two peer
/// connections.
///
/// Bugfix/feature session changes (all confined to this file + the
/// three data-layer files it composes — no schema change, per Rule 7,
/// since none of this is persisted; it's exactly as ephemeral as the
/// existing SDP/ICE signaling this already sits alongside):
///   1. Caller-side "Calling…" -> "Ringing…" via a new `ringing_ack`
///      signaling event (see `isRemoteRinging` on the state).
///   2. `_onPeerConnectionStateChanged` no longer hangs up on the very
///      first `disconnected` tick — that state is frequently transient
///      during/just-after ICE negotiation and often self-heals. A grace
///      timer gives it a real chance to recover before ending the call.
///      `failed` remains terminal (per the WebRTC spec) and still ends
///      immediately — if this fires right after answering, check that
///      `.env`'s TURN_URL/TURN_USERNAME/TURN_CREDENTIAL are real values;
///      STUN-only ICE often can't traverse mobile-carrier NATs at all.
///   3. Incoming video calls now grab the camera/mic (for a live
///      preview) the moment the ring appears, not only after Accept is
///      tapped — mirrors WhatsApp, and `answerCall()` reuses that same
///      session instead of a second `getUserMedia()` call.
///   4. `callConnectedAt` is stamped the moment either side reaches
///      `active`, for the in-call duration timer (UI-only, not
///      persisted — `Call.startedAt`/`endedAt` already covers history).
///   5. `CallSoundPlayer` starts/stops purely off phase transitions.
class CallController extends Notifier<CallSessionState> {
  WebrtcSession? _session;
  SignalingRepository? _signaling;
  final CallSoundPlayer _sound = CallSoundPlayer();

  StreamSubscription<Map<String, dynamic>>? _offerSub;
  StreamSubscription<Map<String, dynamic>>? _answerSub;
  StreamSubscription<Map<String, dynamic>>? _iceSub;
  StreamSubscription<void>? _hangupSub;
  StreamSubscription<void>? _ringingAckSub;

  Map<String, dynamic>? _pendingOffer;
  String? _watchedIncomingCallId;
  Timer? _ringingAckResendTimer;
  Timer? _reconnectGraceTimer;

  @override
  CallSessionState build() {
    // Global incoming-call detection: as soon as a 'ringing' row shows
    // up for me that I didn't place, join its signaling channel and
    // flip to incomingRinging — foreground-only per your confirmed
    // decision, so this only fires while the app (and this provider)
    // is alive.
    ref.listen<Call?>(incomingRingingCallProvider, (previous, next) {
      if (next != null && next.id != _watchedIncomingCallId) {
        _watchedIncomingCallId = next.id;
        _handleIncomingCall(next);
      }
    });
    ref.onDispose(_cleanupSession);
    return CallSessionState.idle;
  }

  WebrtcSession? get session => _session;

  // ---------------------------------------------------------------
  // Caller side
  // ---------------------------------------------------------------

  /// Places a call. Returns false (leaving state untouched) if a call
  /// is already active on this device, or the user isn't signed in.
  Future<bool> startCall({
    required String conversationId,
    required String calleeId,
    required bool isVideo,
  }) async {
    if (!state.isIdle) return false;
    final myId = ref.read(currentSessionProvider)?.user.id;
    if (myId == null) return false;

    state = CallSessionState(
      phase: CallPhase.connecting,
      otherUserId: calleeId,
      isVideo: isVideo,
    );
    _syncSound();

    try {
      final call = await ref.read(callRepositoryProvider).createCall(
            conversationId: conversationId,
            callerId: myId,
            type: isVideo ? 'video' : 'audio',
          );
      state = state.copyWith(phase: CallPhase.outgoingRinging, call: call);
      _syncSound();

      final signaling = SignalingRepository(SupabaseConfig.client, call.id);
      _signaling = signaling;
      await signaling.join();
      _wireSignalingListeners(signaling);

      final session = WebrtcSession();
      _session = session;
      session.onLocalIceCandidate =
          (c) => signaling.sendIceCandidate(WebrtcSession.candidateToJson(c));
      session.onConnectionStateChanged = _onPeerConnectionStateChanged;
      // Grabs the camera immediately (before the offer is even sent) —
      // this is the "WhatsApp opens the camera on the caller side even
      // before the call connects" behavior; nothing new needed here,
      // it already worked this way.
      await session.init(isVideo: isVideo);
      state = state.copyWith(isSpeakerOn: session.isSpeakerOn);

      final offer = await session.createOffer();
      await signaling.sendOffer(offer);
      return true;
    } catch (e) {
      state = state.copyWith(
        phase: CallPhase.ended,
        errorMessage: 'Could not start the call: $e',
      );
      await _cleanupSession();
      state = CallSessionState.idle;
      return false;
    }
  }

  // ---------------------------------------------------------------
  // Callee side
  // ---------------------------------------------------------------

  /// Fired by the [incomingRingingCallProvider] listener in [build].
  /// Joins the call's signaling channel right away, sends the
  /// `ringing_ack` that flips the caller's UI to "Ringing…", and — for
  /// video calls — grabs the camera immediately for a live preview,
  /// before the user has even tapped Accept. Also buffers the offer as
  /// soon as it arrives, so [answerCall] has zero signaling latency.
  Future<void> _handleIncomingCall(Call call) async {
    if (!state.isIdle) return; // already on a call — let it ring out.

    state = CallSessionState(
      phase: CallPhase.incomingRinging,
      call: call,
      otherUserId: call.callerId,
      isVideo: call.isVideo,
    );
    _syncSound();

    final signaling = SignalingRepository(SupabaseConfig.client, call.id);
    _signaling = signaling;
    _wireSignalingListeners(signaling);
    _offerSub ??= signaling.onOffer.listen((offer) => _pendingOffer = offer);
    await signaling.join();

    // Tell the caller we're actually ringing (app running, device
    // online) — this is what flips their screen from "Calling…" to
    // "Ringing…". Sent once immediately, then re-sent every couple of
    // seconds while still ringing, in case the very first broadcast
    // races the caller's listener being wired up (broadcast channels
    // don't replay missed messages, so a single lost packet would
    // otherwise leave the caller stuck on "Calling…" for the whole
    // call).
    unawaited(signaling.sendRingingAck());
    _ringingAckResendTimer?.cancel();
    _ringingAckResendTimer = Timer.periodic(const Duration(seconds: 2), (t) {
      if (state.phase == CallPhase.incomingRinging &&
          state.call?.id == call.id) {
        unawaited(signaling.sendRingingAck());
      } else {
        t.cancel();
      }
    });

    // WhatsApp-style: open the camera preview immediately for an
    // incoming video call, not only after Accept is tapped.
    if (call.isVideo) {
      try {
        final session = WebrtcSession();
        _session = session;
        await session.initLocalMedia(isVideo: true);
        if (state.call?.id == call.id) {
          state = state.copyWith(isSpeakerOn: session.isSpeakerOn);
        }
      } catch (_) {
        // Best-effort preview only — if this fails (e.g. permission
        // denied), answerCall() retries initLocalMedia itself and
        // surfaces the real error there if it still fails.
        _session = null;
      }
    }
  }

  /// Accepts the currently-ringing incoming call.
  Future<bool> answerCall() async {
    if (state.phase != CallPhase.incomingRinging) return false;
    final signaling = _signaling;
    final call = state.call;
    if (signaling == null || call == null) return false;

    _ringingAckResendTimer?.cancel();
    state = state.copyWith(phase: CallPhase.connecting);
    _syncSound();
    try {
      // Reuse the session already opened for the live camera/mic
      // preview during incomingRinging (video calls) instead of
      // grabbing media a second time — avoids a duplicate
      // getUserMedia() call and a jarring re-permission prompt right as
      // the user taps Accept.
      final session = _session ?? WebrtcSession();
      _session = session;
      session.onLocalIceCandidate =
          (c) => signaling.sendIceCandidate(WebrtcSession.candidateToJson(c));
      session.onConnectionStateChanged = _onPeerConnectionStateChanged;
      if (!session.hasLocalMedia) {
        await session.initLocalMedia(isVideo: state.isVideo);
      }
      await session.initPeerConnection();
      state = state.copyWith(isSpeakerOn: session.isSpeakerOn);

      // The offer may not have arrived yet even though the caller
      // sends it almost immediately — wait briefly rather than
      // failing outright.
      final offer = _pendingOffer ?? await signaling.onOffer.first;
      final answer = await session.createAnswer(offer);
      await signaling.sendAnswer(answer);

      await ref
          .read(callRepositoryProvider)
          .updateStatus(callId: call.id, status: 'ongoing');
      state = state.copyWith(
        phase: CallPhase.active,
        callConnectedAt: DateTime.now(),
      );
      _syncSound();
      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: 'Could not answer the call: $e');
      await endCall();
      return false;
    }
  }

  /// Rejects the currently-ringing incoming call without answering.
  Future<void> declineCall() async {
    if (state.phase != CallPhase.incomingRinging) return;
    _ringingAckResendTimer?.cancel();
    final call = state.call;
    if (call != null) {
      try {
        await ref
            .read(callRepositoryProvider)
            .updateStatus(callId: call.id, status: 'declined');
      } catch (_) {
        // Best-effort — see endCall().
      }
      await _sendHangupBestEffort();
    }
    await _endLocally();
  }

  // ---------------------------------------------------------------
  // Shared (both sides)
  // ---------------------------------------------------------------

  /// Ends an active call, or cancels one still ringing. A call ended
  /// before it ever reached 'active' is recorded as 'missed' — matches
  /// WhatsApp's own framing of an unanswered call from either side's
  /// action, 'declined' is reserved for the callee's explicit reject
  /// (see [declineCall]).
  Future<void> endCall() async {
    final call = state.call;
    if (call != null) {
      final reachedActive = state.phase == CallPhase.active;
      try {
        await ref.read(callRepositoryProvider).updateStatus(
              callId: call.id,
              status: reachedActive ? 'ended' : 'missed',
              setEndedNow: reachedActive,
            );
      } catch (_) {
        // Best-effort — see _sendHangupBestEffort's doc comment. The
        // call must end on THIS device regardless of whether the
        // shared history row could be written (bad network, a stale
        // token, etc.); leaving the screen stuck waiting on that write
        // is worse than a call-history row briefly out of sync with
        // what actually happened locally.
      }
      await _sendHangupBestEffort();
    }
    await _endLocally();
  }

  /// The other side hung up (cancelled, declined, or ended) — they
  /// already wrote the terminal `calls` status themselves, so this
  /// side only needs to tear down its own local session.
  void _onRemoteHangup() {
    unawaited(_endLocally());
  }

  Future<void> _endLocally() async {
    state = state.copyWith(phase: CallPhase.ended);
    _syncSound();
    await _cleanupSession();
    state = CallSessionState.idle;
  }

  void toggleMute() {
    _session?.toggleMute();
    state = state.copyWith(isMuted: _session?.isMuted ?? false);
  }

  void toggleCamera() {
    _session?.toggleCamera();
    state = state.copyWith(isCameraOff: _session?.isCameraOff ?? false);
  }

  Future<void> switchCamera() => _session?.switchCamera() ?? Future.value();

  /// Ear-speaker <-> phone-speaker toggle, available both while ringing
  /// (the caller's mic/speaker session is already live at that point)
  /// and during an active call.
  Future<void> toggleSpeaker() async {
    await _session?.toggleSpeaker();
    state = state.copyWith(isSpeakerOn: _session?.isSpeakerOn ?? false);
  }

  /// Best-effort hangup broadcast, bounded so a stuck signaling socket
  /// can never block Cancel/End from completing locally. Not fatal if
  /// it fails or times out either way — the peer also detects the
  /// dropped RTCPeerConnection via [_onPeerConnectionStateChanged] and
  /// ends locally on its own.
  Future<void> _sendHangupBestEffort() async {
    try {
      await _signaling?.sendHangup().timeout(const Duration(seconds: 3));
    } catch (_) {}
  }

  // ---------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------

  void _wireSignalingListeners(SignalingRepository signaling) {
    _answerSub = signaling.onAnswer.listen((answer) async {
      final session = _session;
      final call = state.call;
      if (session == null || call == null) return;
      await session.setRemoteDescription(answer);
      await ref
          .read(callRepositoryProvider)
          .updateStatus(callId: call.id, status: 'ongoing');
      state = state.copyWith(
        phase: CallPhase.active,
        callConnectedAt: DateTime.now(),
      );
      _syncSound();
    });

    _iceSub = signaling.onIceCandidate.listen((candidate) {
      _session?.addRemoteIceCandidate(candidate);
    });

    _hangupSub = signaling.onHangup.listen((_) => _onRemoteHangup());

    // Caller-side "Calling…" -> "Ringing…" — harmless no-op on the
    // callee side, since `self: false` means a client never receives
    // its own broadcasts back anyway.
    _ringingAckSub = signaling.onRingingAck.listen((_) {
      if (!state.isRemoteRinging) {
        state = state.copyWith(isRemoteRinging: true);
      }
    });
  }

  void _onPeerConnectionStateChanged(RTCPeerConnectionState pcState) {
    switch (pcState) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        _reconnectGraceTimer?.cancel();
        _reconnectGraceTimer = null;
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        // 'disconnected' is frequently transient (a brief Wi-Fi/cellular
        // handoff, a slow ICE re-check) and often self-heals back to
        // 'connected' within a few seconds — hanging up on the very
        // first tick of it is why a call could look like it "cut
        // instantly" right after being answered. Give it a real grace
        // window before treating it as a genuine drop.
        _reconnectGraceTimer ??= Timer(const Duration(seconds: 8), () {
          if (!state.isIdle) unawaited(endCall());
        });
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        // 'failed' is terminal per the WebRTC spec — ICE could not find
        // any working path at all. If this fires right after answering,
        // check that `.env`'s TURN_URL/TURN_USERNAME/TURN_CREDENTIAL are
        // real values (see WebrtcConfig's doc comment and PRD.md §11's
        // honest limitation note) — STUN-only ICE frequently can't
        // traverse mobile-carrier NATs, and no app-side retry logic
        // fixes a missing/misconfigured TURN server.
        unawaited(endCall());
        break;
      default:
        break;
    }
  }

  /// Starts/stops the ring/dial tone purely off the current phase — the
  /// tone plays from the moment a call starts dialing/ringing until it
  /// becomes active (or ends/is declined/cancelled).
  void _syncSound() {
    const ringingPhases = {
      CallPhase.outgoingRinging,
      CallPhase.incomingRinging,
      CallPhase.connecting,
    };
    if (ringingPhases.contains(state.phase)) {
      unawaited(_sound.start());
    } else {
      unawaited(_sound.stop());
    }
  }

  Future<void> _cleanupSession() async {
    await _offerSub?.cancel();
    await _answerSub?.cancel();
    await _iceSub?.cancel();
    await _hangupSub?.cancel();
    await _ringingAckSub?.cancel();
    _offerSub = null;
    _answerSub = null;
    _iceSub = null;
    _hangupSub = null;
    _ringingAckSub = null;
    _pendingOffer = null;
    _watchedIncomingCallId = null;
    _ringingAckResendTimer?.cancel();
    _ringingAckResendTimer = null;
    _reconnectGraceTimer?.cancel();
    _reconnectGraceTimer = null;
    unawaited(_sound.stop());

    // flutter_webrtc's native teardown (RTCPeerConnection.close/dispose,
    // track.stop()) and the signaling channel's removeChannel call are
    // both plugin/socket calls that can occasionally hang on-device
    // rather than throw. Timing each out means a stuck native call can
    // never again leave Cancel/End looking "jammed" — the call always
    // finishes ending locally within a few seconds, worst case.
    final session = _session;
    _session = null;
    if (session != null) {
      try {
        await session.dispose().timeout(const Duration(seconds: 3));
      } catch (_) {}
    }

    final signaling = _signaling;
    _signaling = null;
    if (signaling != null) {
      try {
        await signaling.dispose().timeout(const Duration(seconds: 3));
      } catch (_) {}
    }
  }
}

final callControllerProvider =
    NotifierProvider<CallController, CallSessionState>(CallController.new);
