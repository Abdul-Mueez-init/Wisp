// lib/features/calls/data/signaling_repository.dart
import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// One `SignalingRepository` instance is created per active call. It
/// owns a dedicated broadcast-only `RealtimeChannel` named
/// `call:{call_id}` — deliberately NOT the shared presence channel
/// (`PresenceRepository`) or a `typing_status`-style table (see the
/// Phase 10 decision, confirmed): SDP offers/answers and a stream of
/// ICE candidates are too chatty and too ephemeral to justify DB
/// writes/RLS overhead per message, and a fresh channel per call keeps
/// one call's signaling traffic from ever reaching a peer who isn't in
/// that call. The `calls` table (CallRepository) remains the only
/// place coarse call state (ringing/ongoing/ended) is persisted.
///
/// `self: false` on the channel means this client never receives its
/// own broadcasts back — no need to filter out self-sent events.
class SignalingRepository {
  SignalingRepository(this._client, this.callId);

  final SupabaseClient _client;
  final String callId;

  RealtimeChannel? _channel;

  final _offerController = StreamController<Map<String, dynamic>>.broadcast();
  final _answerController = StreamController<Map<String, dynamic>>.broadcast();
  final _iceCandidateController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _hangupController = StreamController<void>.broadcast();

  Stream<Map<String, dynamic>> get onOffer => _offerController.stream;
  Stream<Map<String, dynamic>> get onAnswer => _answerController.stream;
  Stream<Map<String, dynamic>> get onIceCandidate =>
      _iceCandidateController.stream;
  Stream<void> get onHangup => _hangupController.stream;

  /// Joins this call's dedicated channel. Must be called (and its
  /// returned future awaited, or at least started) before any `send*`
  /// call — broadcasts sent before the channel finishes subscribing
  /// are dropped by Supabase Realtime.
  Future<void> join() {
    final completer = Completer<void>();
    final channel = _client.channel(
      'call:$callId',
      opts: const RealtimeChannelConfig(self: false),
    );
    _channel = channel;

    channel
        .onBroadcast(
          event: 'offer',
          callback: (payload) => _offerController.add(payload),
        )
        .onBroadcast(
          event: 'answer',
          callback: (payload) => _answerController.add(payload),
        )
        .onBroadcast(
          event: 'ice-candidate',
          callback: (payload) => _iceCandidateController.add(payload),
        )
        .onBroadcast(
          event: 'hangup',
          callback: (_) => _hangupController.add(null),
        )
        .subscribe((status, error) {
      if (status == RealtimeSubscribeStatus.subscribed &&
          !completer.isCompleted) {
        completer.complete();
      } else if (status == RealtimeSubscribeStatus.channelError &&
          !completer.isCompleted) {
        completer.completeError(error ?? Exception('Signaling channel error'));
      }
    });

    return completer.future;
  }

  Future<void> sendOffer(Map<String, dynamic> sdp) => _send('offer', sdp);

  Future<void> sendAnswer(Map<String, dynamic> sdp) => _send('answer', sdp);

  Future<void> sendIceCandidate(Map<String, dynamic> candidate) =>
      _send('ice-candidate', candidate);

  Future<void> sendHangup() => _send('hangup', const {});

  Future<void> _send(String event, Map<String, dynamic> payload) async {
    final channel = _channel;
    if (channel == null) return;
    await channel.sendBroadcastMessage(event: event, payload: payload);
  }

  /// Leaves the channel and closes local stream controllers. Safe to
  /// call multiple times / even if [join] was never called.
  Future<void> dispose() async {
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      await _client.removeChannel(channel);
    }
    await _offerController.close();
    await _answerController.close();
    await _iceCandidateController.close();
    await _hangupController.close();
  }
}
