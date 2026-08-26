import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/failure.dart';
import '../../../models/message.dart';
import '../../../models/message_status.dart';

/// All `messages`/`message_status` reads and writes go through here
/// (rules.md Rule 8 pattern extended to the chat domain).
class MessageRepository {
  MessageRepository(this._client);
  final SupabaseClient _client;

  /// Realtime message stream for one conversation, oldest first.
  /// Uses a single `.eq()` filter deliberately — supabase_flutter's
  /// `.stream()` is documented to misbehave with more than one chained
  /// filter, so conversation scoping is the only server-side filter and
  /// ordering/mapping happens after.
  Stream<List<Message>> watchMessages(String conversationId) {
    return _client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId)
        .order('created_at')
        .map((rows) => rows.map(Message.fromJson).toList());
  }

  /// Every `message_status` row visible to the current user under RLS:
  /// their own rows as a recipient, plus (per the added
  /// `message_status_select_sender` policy) rows for messages they
  /// sent. Deliberately unfiltered beyond RLS itself — `.stream()`
  /// doesn't support the `inFilter` this table would otherwise need,
  /// and RLS already bounds this to exactly what this user should see.
  /// Callers filter client-side to the message ids they care about.
  Stream<List<MessageStatus>> watchMyVisibleStatuses() {
    return _client.from('message_status').stream(primaryKey: ['id']).map(
        (rows) => rows.map(MessageStatus.fromJson).toList());
  }

  Future<void> sendTextMessage({
    required String conversationId,
    required String senderId,
    required String content,
  }) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;
    try {
      await _client.from('messages').insert({
        'conversation_id': conversationId,
        'sender_id': senderId,
        'type': 'text',
        'content': trimmed,
      });
    } on PostgrestException catch (e) {
      throw SupabaseFailure(e.message);
    }
  }

  /// Generic media-message insert — covers 'image' now (Batch 5a) and
  /// 'video'/'document' from Batch 5b on, since all three share the
  /// same shape: a storage path in `media_url`, an optional caption in
  /// `content`. [messageId] is generated client-side by the caller so
  /// it can be reused as the storage path segment (see
  /// MediaRepository) — inserted explicitly instead of relying on the
  /// column default.
  Future<void> sendMediaMessage({
    required String messageId,
    required String conversationId,
    required String senderId,
    required String type,
    required String mediaPath,
    String? caption,
  }) async {
    try {
      final trimmedCaption = caption?.trim();
      await _client.from('messages').insert({
        'id': messageId,
        'conversation_id': conversationId,
        'sender_id': senderId,
        'type': type,
        'content': (trimmedCaption?.isEmpty ?? true) ? null : trimmedCaption,
        'media_url': mediaPath,
      });
    } on PostgrestException catch (e) {
      throw SupabaseFailure(e.message);
    }
  }

  /// Inserts a 'delivered' `message_status` row (as the recipient
  /// themselves — required by the `message_status_insert_own` RLS
  /// policy) for any message in [conversationId] not sent by [myId]
  /// that doesn't already have a status row from [myId].
  Future<void> markDelivered({
    required String conversationId,
    required String myId,
  }) async {
    try {
      final incoming = await _incomingMessageIds(conversationId, myId);
      if (incoming.isEmpty) return;

      final alreadyTracked = await _trackedMessageIds(incoming, myId);
      final toInsert = incoming
          .where((id) => !alreadyTracked.contains(id))
          .map((id) => {
                'message_id': id,
                'user_id': myId,
                'status': 'delivered',
              })
          .toList();

      if (toInsert.isNotEmpty) {
        await _client.from('message_status').insert(toInsert);
      }
    } on PostgrestException catch (e) {
      throw SupabaseFailure(e.message);
    }
  }

  /// Upgrades every incoming message's status to 'read' for [myId] —
  /// updates existing rows (e.g. 'delivered' → 'read') and inserts any
  /// still-missing rows directly as 'read'.
  Future<void> markRead({
    required String conversationId,
    required String myId,
  }) async {
    try {
      final incoming = await _incomingMessageIds(conversationId, myId);
      if (incoming.isEmpty) return;

      await _client
          .from('message_status')
          .update({
            'status': 'read',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('user_id', myId)
          .inFilter('message_id', incoming);

      final stillTracked = await _trackedMessageIds(incoming, myId);
      final toInsert = incoming
          .where((id) => !stillTracked.contains(id))
          .map((id) => {'message_id': id, 'user_id': myId, 'status': 'read'})
          .toList();

      if (toInsert.isNotEmpty) {
        await _client.from('message_status').insert(toInsert);
      }
    } on PostgrestException catch (e) {
      throw SupabaseFailure(e.message);
    }
  }

  Future<List<String>> _incomingMessageIds(
    String conversationId,
    String myId,
  ) async {
    final rows = await _client
        .from('messages')
        .select('id')
        .eq('conversation_id', conversationId)
        .neq('sender_id', myId);
    return (rows as List).map((r) => r['id'] as String).toList();
  }

  Future<Set<String>> _trackedMessageIds(
    List<String> messageIds,
    String myId,
  ) async {
    final rows = await _client
        .from('message_status')
        .select('message_id')
        .eq('user_id', myId)
        .inFilter('message_id', messageIds);
    return (rows as List).map((r) => r['message_id'] as String).toSet();
  }
}
