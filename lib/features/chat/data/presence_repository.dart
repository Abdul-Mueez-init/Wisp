import 'package:supabase_flutter/supabase_flutter.dart';

/// Wraps a single, app-wide Supabase Realtime Presence channel — this is
/// the "via Supabase Presence" mechanism ERD.md/plan.md call for.
///
/// Presence itself is ephemeral and scoped to this socket connection, so
/// it is *not* what other users read from directly. Instead, this
/// repository's job is to flip the persisted `profiles.is_online` /
/// `last_seen_at` columns (ERD.md: "updated via presence channel") in
/// step with this client's own presence state. Other clients then read
/// online status the same way they read everything else realtime in
/// this app: a `StreamProvider` on the `profiles` table (see
/// `ProfileRepository.watchProfile`), matching the pattern already used
/// for messages/message_status.
class PresenceRepository {
  PresenceRepository(this._client);
  final SupabaseClient _client;

  static const _channelName = 'presence:online-users';

  RealtimeChannel? _channel;

  /// Joins the shared presence channel and tracks this user as present.
  /// No-ops if already tracking (e.g. a duplicate app-resume call).
  Future<void> track(String userId) async {
    if (_channel != null) return;
    final channel = _client.channel(_channelName);
    _channel = channel;
    channel.subscribe((status, error) async {
      if (status == RealtimeSubscribeStatus.subscribed) {
        await channel.track({'user_id': userId});
      }
    });
  }

  /// Leaves the presence channel. Safe to call even if never tracked.
  Future<void> untrack() async {
    final channel = _channel;
    _channel = null;
    if (channel == null) return;
    await channel.untrack();
    await _client.removeChannel(channel);
  }
}
