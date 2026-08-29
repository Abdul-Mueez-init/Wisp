// lib/features/calls/providers/call_controller.dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show RTCPeerConnectionState;

import '../../../config/supabase_config.dart';
import '../../../models/call.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/signaling_repository.dart';
import '../data/webrtc_session.dart';
import 'call_provider.dart';
import 'call_session_state.dart';

/// Owns the whole call lifecycle end to end: place a call, detect and
/// answer/decline an incoming one, and hang up — wiring
/// [SignalingRepository] (SDP/ICE transport), [WebrtcSession] (the
/// peer connection itself), and [CallRepository] (persisted
/// ringing/ongoing/ended/missed/declined history) together. Same
/// `Notifier<State>` shape as `LiveLocationController` in
/// features/location — a single long-lived controller for a lifecycle
/// with an explicit start/active/stop shape, not a one-shot
/// `AsyncNotifier` action.
///
/// Only one call is ever active on this device at a time — matches
/// PRD.md §11's 1-on-1-only scope and avoids juggling two peer
/// connections.
class CallController extends Notifier<CallSessionState> {
  WebrtcSession? _session;
  SignalingRepository? _signaling;

  StreamSubscription<Map<String, dynamic>>? _offerSub;
  StreamSubscription<Map<String, dynamic>>? _answerSub;
  StreamSubscription<Map<String, dynamic>>? _iceSub;
  StreamSubscription<void>? _hangupSub;

  Map<String, dynamic>? _pendingOffer;
  String? _watchedIncomingCallId;

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

    try {
      final call = await ref.read(callRepositoryProvider).createCall(
            conversationId: conversationId,
            callerId: myId,
            type: isVideo ? 'video' : 'audio',
          );
      state = state.copyWith(phase: CallPhase.outgoingRinging, call: call);

      final signaling = SignalingRepository(SupabaseConfig.client, call.id);
      _signaling = signaling;
      await signaling.join();
      _wireSignalingListeners(signaling);

      final session = WebrtcSession();
      _session = session;
      session.onLocalIceCandidate =
          (c) => signaling.sendIceCandidate(WebrtcSession.candidateToJson(c));
      session.onConnectionStateChanged = _onPeerConnectionStateChanged;
      await session.init(isVideo: isVideo);

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
  /// Joins the call's signaling channel right away and buffers the
  /// offer as soon as it arrives, so [answerCall] has zero signaling
  /// latency once the user actually taps Accept.
  Future<void> _handleIncomingCall(Call call) async {
    if (!state.isIdle) return; // already on a call — let it ring out.

    state = CallSessionState(
      phase: CallPhase.incomingRinging,
      call: call,
      otherUserId: call.callerId,
      isVideo: call.isVideo,
    );

    final signaling = SignalingRepository(SupabaseConfig.client, call.id);
    _signaling = signaling;
    _wireSignalingListeners(signaling);
    _offerSub ??= signaling.onOffer.listen((offer) => _pendingOffer = offer);
    await signaling.join();
  }

  /// Accepts the currently-ringing incoming call.
  Future<bool> answerCall() async {
    if (state.phase != CallPhase.incomingRinging) return false;
    final signaling = _signaling;
    final call = state.call;
    if (signaling == null || call == null) return false;

    state = state.copyWith(phase: CallPhase.connecting);
    try {
      final session = WebrtcSession();
      _session = session;
      session.onLocalIceCandidate =
          (c) => signaling.sendIceCandidate(WebrtcSession.candidateToJson(c));
      session.onConnectionStateChanged = _onPeerConnectionStateChanged;
      await session.init(isVideo: state.isVideo);

      // The offer may not have arrived yet even though the caller
      // sends it almost immediately — wait briefly rather than
      // failing outright.
      final offer = _pendingOffer ?? await signaling.onOffer.first;
      final answer = await session.createAnswer(offer);
      await signaling.sendAnswer(answer);

      await ref
          .read(callRepositoryProvider)
          .updateStatus(callId: call.id, status: 'ongoing');
      state = state.copyWith(phase: CallPhase.active);
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
    final call = state.call;
    if (call != null) {
      await ref
          .read(callRepositoryProvider)
          .updateStatus(callId: call.id, status: 'declined');
      await ref.read(callRepositoryProvider).insertCallEventMessage(
            conversationId: call.conversationId,
            callerId: call.callerId,
            callId: call.id,
          );
      await _signaling?.sendHangup();
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
      await ref.read(callRepositoryProvider).updateStatus(
            callId: call.id,
            status: reachedActive ? 'ended' : 'missed',
            setEndedNow: reachedActive,
          );
      await ref.read(callRepositoryProvider).insertCallEventMessage(
            conversationId: call.conversationId,
            callerId: call.callerId,
            callId: call.id,
          );
      await _signaling?.sendHangup();
    }
    await _endLocally();
  }

  /// The other side hung up (cancelled, declined, or ended) — they
  /// already wrote the terminal `calls` status and the call-event
  /// message themselves, so this side only needs to tear down its own
  /// local session.
  void _onRemoteHangup() {
    unawaited(_endLocally());
  }

  Future<void> _endLocally() async {
    state = state.copyWith(phase: CallPhase.ended);
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
      state = state.copyWith(phase: CallPhase.active);
    });

    _iceSub = signaling.onIceCandidate.listen((candidate) {
      _session?.addRemoteIceCandidate(candidate);
    });

    _hangupSub = signaling.onHangup.listen((_) => _onRemoteHangup());
  }

  void _onPeerConnectionStateChanged(RTCPeerConnectionState pcState) {
    if (pcState == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
        pcState == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
      // Best-effort: a dropped connection ends the call locally rather
      // than leaving the UI stuck in 'active' with dead media.
      unawaited(endCall());
    }
  }

  Future<void> _cleanupSession() async {
    await _offerSub?.cancel();
    await _answerSub?.cancel();
    await _iceSub?.cancel();
    await _hangupSub?.cancel();
    _offerSub = null;
    _answerSub = null;
    _iceSub = null;
    _hangupSub = null;
    _pendingOffer = null;
    _watchedIncomingCallId = null;

    await _session?.dispose();
    _session = null;
    await _signaling?.dispose();
    _signaling = null;
  }
}

final callControllerProvider =
    NotifierProvider<CallController, CallSessionState>(CallController.new);
