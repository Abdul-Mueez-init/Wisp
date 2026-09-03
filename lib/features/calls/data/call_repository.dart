// lib/features/calls/data/call_repository.dart
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/failure.dart';
import '../../../core/utils/resilient_realtime_stream.dart';
import '../../../models/call.dart';

/// All `calls` table reads/writes go through here (rules.md Rule 8
/// pattern extended to the calls domain, matching MessageRepository).
/// WebRTC signaling itself (SDP/ICE) does NOT go through this class —
/// see SignalingRepository. This repo only owns the coarse-grained
/// history state ERD.md's `calls` table models: ringing/ongoing/ended/
/// missed/declined, plus started_at/ended_at for the Calls tab list.
class CallRepository {
  CallRepository(this._client);
  final SupabaseClient _client;

  /// Creates a new 'ringing' call row and returns it (with its
  /// server-generated id) so the caller can immediately open a
  /// per-call signaling channel keyed on that id. `started_at` is set
  /// now — see Call model's doc comment on why "ringing time" is used
  /// in the absence of a `created_at` column.
  Future<Call> createCall({
    required String conversationId,
    required String callerId,
    required String type, // 'audio' | 'video'
  }) async {
    try {
      final row = await _client
          .from('calls')
          .insert({
            'conversation_id': conversationId,
            'caller_id': callerId,
            'type': type,
            'status': 'ringing',
            'started_at': DateTime.now().toIso8601String(),
          })
          .select()
          .single();
      return Call.fromJson(row);
    } on PostgrestException catch (e) {
      throw SupabaseFailure(e.message);
    }
  }

  /// Status transitions: ringing -> ongoing -> ended, or ringing ->
  /// missed/declined. `endedAt` is only ever set when moving to
  /// 'ended' (a missed/declined call never "ends" in the duration
  /// sense — see Call.duration).
  Future<void> updateStatus({
    required String callId,
    required String status,
    bool setEndedNow = false,
  }) async {
    try {
      await _client.from('calls').update({
        'status': status,
        if (setEndedNow) 'ended_at': DateTime.now().toIso8601String(),
      }).eq('id', callId);
    } on PostgrestException catch (e) {
      throw SupabaseFailure(e.message);
    }
  }

  Future<Call?> fetchCall(String callId) async {
    try {
      final row =
          await _client.from('calls').select().eq('id', callId).maybeSingle();
      return row == null ? null : Call.fromJson(row);
    } on PostgrestException catch (e) {
      throw SupabaseFailure(e.message);
    }
  }

  /// Realtime stream of every `calls` row this user can see under RLS
  /// (i.e. every conversation they're a member of). Deliberately
  /// unfiltered beyond RLS — same reasoning as
  /// `MessageRepository.watchMyVisibleStatuses` — since `.stream()`
  /// doesn't support the multi-conversation `inFilter` the Calls tab
  /// would otherwise need. Callers sort/group client-side.
  ///
  /// wisp_fixes.txt permanent fix: wrapped in [resilientRealtimeStream]
  /// so this channel resubscribes automatically after a token refresh
  /// instead of staying stuck on a stale token post-background (see
  /// that helper's doc comment for the full root cause). This is the
  /// stream both the Calls tab and the global incoming-call detector
  /// (`incomingRingingCallProvider`) depend on, so it's the one that
  /// most needed to be self-healing.
  Stream<List<Call>> watchMyVisibleCalls() {
    return resilientRealtimeStream(
      _client,
      () => _client.from('calls').stream(
          primaryKey: ['id']).map((rows) => rows.map(Call.fromJson).toList()),
    );
  }

  /// Single-conversation call stream — used by ChatDetailScreen to
  /// detect an incoming/active call for the conversation it's
  /// currently showing (e.g. to render an "ongoing call" banner).
  Stream<List<Call>> watchCallsForConversation(String conversationId) {
    return resilientRealtimeStream(
      _client,
      () => _client
          .from('calls')
          .stream(primaryKey: ['id'])
          .eq('conversation_id', conversationId)
          .map((rows) => rows.map(Call.fromJson).toList()),
    );
  }
}
