import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/failure.dart';

/// All `typing_status` reads/writes go through here (rules.md Rule 8
/// pattern extended to the chat domain, matching MessageRepository).
class TypingRepository {
  TypingRepository(this._client);
  final SupabaseClient _client;

  /// Every `is_typing = true` user id for [conversationId], most-recent
  /// first. Staleness (a client that died mid-typing without clearing
  /// its row) is filtered client-side by [TypingRepository.isFresh] via
  /// callers — a single `.eq()` filter is used here deliberately, same
  /// reasoning as `MessageRepository.watchMessages`.
  Stream<List<Map<String, dynamic>>> watchTypingRows(String conversationId) {
    return _client
        .from('typing_status')
        .stream(primaryKey: ['conversation_id', 'user_id']).eq(
            'conversation_id', conversationId);
  }

  /// Upserts this user's typing state for a conversation. Composite PK
  /// (conversation_id, user_id) means this naturally updates-in-place
  /// on repeat calls.
  Future<void> setTyping({
    required String conversationId,
    required String userId,
    required bool isTyping,
  }) async {
    try {
      await _client.from('typing_status').upsert({
        'conversation_id': conversationId,
        'user_id': userId,
        'is_typing': isTyping,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } on PostgrestException catch (e) {
      throw SupabaseFailure(e.message);
    }
  }

  /// A typing row older than this is treated as stale (e.g. the sender's
  /// app closed/crashed without clearing it) and ignored, since nothing
  /// server-side expires these rows automatically.
  static const staleAfter = Duration(seconds: 8);

  static bool isFresh(Map<String, dynamic> row) {
    final updatedAt = DateTime.tryParse(row['updated_at'] as String? ?? '');
    if (updatedAt == null) return false;
    return DateTime.now().difference(updatedAt) < staleAfter;
  }

  /// its row) is filtered client-side by [TypingRepository.isFresh] via
  /// callers — a single `.eq()` filter is used here deliberately (the
  /// same `.stream()` chained-filter caveat `MessageRepository` used to
  /// document). `typing_status` is small and ephemeral by nature, so
  /// unlike `messages` it wasn't in scope for Phase D's pagination work.
}
