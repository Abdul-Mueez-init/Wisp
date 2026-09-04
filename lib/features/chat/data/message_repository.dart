// lib/features/chat/data/message_repository.dart
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/failure.dart';
import '../../../models/message.dart';
import '../../../models/message_status.dart';
import 'message_event.dart';

/// All `messages`/`message_status` reads and writes go through here
/// (rules.md Rule 8 pattern extended to the chat domain).
class MessageRepository {
  MessageRepository(this._client);
  final SupabaseClient _client;

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

  /// Batch 8 — one-shot fetch of the most recent messages in a
  /// conversation, oldest first. Originally written for
  /// `AiAgentController`'s context transcript (PRD.md §10: "context of
  /// recent chat history... not just the single message it's mentioned
  /// in"); Phase D also reuses this unchanged as `ChatMessagesController`'s
  /// *initial page* fetch — same "most recent N, oldest-first" shape,
  /// just a different caller and a larger default `limit`.
  Future<List<Message>> fetchRecentMessages({
    required String conversationId,
    int limit = 20,
  }) async {
    try {
      final rows = await _client
          .from('messages')
          .select()
          .eq('conversation_id', conversationId)
          .order('created_at', ascending: false)
          .limit(limit);
      return (rows as List)
          .map((r) => Message.fromJson(r as Map<String, dynamic>))
          .toList()
          .reversed
          .toList();
    } on PostgrestException catch (e) {
      throw SupabaseFailure(e.message);
    }
  }

  /// Phase D (WISP_PERFORMANCE_HANDOFF.md §11) — the *next* page of
  /// history, strictly older than [before]. Same "desc query, then
  /// reverse to oldest-first" shape as [fetchRecentMessages], just with
  /// a `created_at` cursor so `ChatMessagesController.loadOlder()` can
  /// keep walking backward through a conversation's history one bounded
  /// page at a time instead of ever re-fetching everything already
  /// loaded.
  Future<List<Message>> fetchOlderMessages({
    required String conversationId,
    required DateTime before,
    int limit = 30,
  }) async {
    try {
      final rows = await _client
          .from('messages')
          .select()
          .eq('conversation_id', conversationId)
          .lt('created_at', before.toIso8601String())
          .order('created_at', ascending: false)
          .limit(limit);
      return (rows as List)
          .map((r) => Message.fromJson(r as Map<String, dynamic>))
          .toList()
          .reversed
          .toList();
    } on PostgrestException catch (e) {
      throw SupabaseFailure(e.message);
    }
  }

  /// Phase D — replaces the old `watchMessages()` full-snapshot
  /// `.stream()` (which re-fetched and re-emitted the *entire*
  /// conversation's message list on every single insert/update, an
  /// amount of work that grows without bound as a conversation ages —
  /// WISP_PERFORMANCE_HANDOFF.md §11's core complaint) with a
  /// conversation-scoped Realtime channel that only ever pushes the one
  /// row that actually changed. `ChatMessagesController` is the only
  /// intended caller: it merges each [MessageEvent] into its own
  /// bounded, paginated local collection rather than trusting the
  /// backend to keep handing back a full list.
  ///
  /// Filtered server-side to [conversationId] via `PostgresChangeFilter`
  /// so this device only receives wire traffic for the conversation
  /// it's actually looking at — RLS (`messages_select_member`) still
  /// applies underneath regardless; this filter is purely to avoid
  /// paying for every other conversation's events too.
  ///
  /// Returns the raw [RealtimeChannel] so the caller owns its lifecycle
  /// (`SupabaseConfig.client.removeChannel(...)` on dispose) — this
  /// repository doesn't track open channels itself, same "caller owns
  /// what it opens" shape as `LocationRepository`'s live-tracking
  /// stream subscriptions.
  RealtimeChannel watchConversationEvents({
    required String conversationId,
    required void Function(MessageEvent event) onEvent,
  }) {
    final filter = PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'conversation_id',
      value: conversationId,
    );
    final channel = _client.channel('messages-$conversationId');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: filter,
          callback: (payload) => onEvent(
            MessageEvent.insert(Message.fromJson(payload.newRecord)),
          ),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'messages',
          filter: filter,
          callback: (payload) => onEvent(
            MessageEvent.update(Message.fromJson(payload.newRecord)),
          ),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'messages',
          filter: filter,
          callback: (payload) {
            final oldId = payload.oldRecord['id'] as String?;
            if (oldId != null) onEvent(MessageEvent.delete(oldId));
          },
        )
        .subscribe();
    return channel;
  }

  /// Batch 8 — inserts the embedded AI agent's reply as its own
  /// `messages` row: `sender_id` null, `is_ai_message` true, exactly
  /// the shape ERD.md's `messages.sender_id` comment ("nullable if
  /// sender is the AI agent") anticipated. Passes `messages_insert_member`
  /// RLS the same way every other insert in this file does — the
  /// *caller* is a real member of the conversation; the policy has no
  /// separate check on `sender_id` itself, so this doesn't need a
  /// service-role key or a new policy.
  Future<void> sendAiMessage({
    required String conversationId,
    required String content,
  }) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;
    try {
      await _client.from('messages').insert({
        'conversation_id': conversationId,
        'sender_id': null,
        'is_ai_message': true,
        'type': 'text',
        'content': trimmed,
      });
    } on PostgrestException catch (e) {
      throw SupabaseFailure(e.message);
    }
  }

  Future<String?> sendTextMessage({
    required String conversationId,
    required String senderId,
    required String content,
  }) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return null;
    try {
      final row = await _client
          .from('messages')
          .insert({
            'conversation_id': conversationId,
            'sender_id': senderId,
            'type': 'text',
            'content': trimmed,
          })
          .select('id')
          .single();
      return row['id'] as String?;
    } on PostgrestException catch (e) {
      throw SupabaseFailure(e.message);
    }
  }

  /// Batch: Phase 7 translation. Updates a text message's own row with
  /// the detected source language and (if applicable) its translation,
  /// after the message has already been inserted and shown — same
  /// "insert now, update in place moments later" shape as
  /// `updateLiveLocationPin`. Requires `messages_update_own`-style
  /// self-update, already granted per the Phase 5e RLS migration.
  Future<void> updateTranslation({
    required String messageId,
    required String originalLanguage,
    String? translatedContent,
  }) async {
    try {
      await _client.from('messages').update({
        'original_language': originalLanguage,
        'translated_content': translatedContent,
      }).eq('id', messageId);
    } on PostgrestException catch (e) {
      throw SupabaseFailure(e.message);
    }
  }

  /// Batch: Phase 9 voice transcription + action extraction. Same
  /// "insert now, update in place moments later" shape as
  /// [updateTranslation]/`updateLiveLocationPin` above — requires the
  /// same `messages_update_own`-style self-update RLS already granted
  /// for those, nothing new to migrate. [actions] is passed straight
  /// through to the `voice_actions` jsonb column (null when the
  /// transcript had no actionable content — see
  /// `VoiceTranscriptionRepository`).
  Future<void> updateVoiceTranscription({
    required String messageId,
    required String transcript,
    Map<String, dynamic>? actions,
  }) async {
    try {
      await _client.from('messages').update({
        'voice_transcript': transcript,
        'voice_actions': actions,
      }).eq('id', messageId);
    } on PostgrestException catch (e) {
      throw SupabaseFailure(e.message);
    }
  }

  /// Small helper for Phase 7's fire-and-forget translation step —
  /// `sendTextMessage` doesn't return the inserted row's id, so this
  /// finds it by (conversation, sender, exact content, most recent).
  /// Fine at demo scale; not a general-purpose lookup.
  Future<String?> findMostRecentTextMessage({
    required String conversationId,
    required String senderId,
    required String content,
  }) async {
    try {
      final row = await _client
          .from('messages')
          .select('id')
          .eq('conversation_id', conversationId)
          .eq('sender_id', senderId)
          .eq('type', 'text')
          .eq('content', content)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      return row?['id'] as String?;
    } on PostgrestException catch (e) {
      throw SupabaseFailure(e.message);
    }
  }

  /// Generic media-message insert — covers 'image'/'video'/'document'/
  /// 'voice', all sharing the same shape: a storage path in
  /// `media_url`, an optional caption in `content`. [messageId] is
  /// generated client-side by the caller so it can be reused as the
  /// storage path segment (see MediaRepository) — inserted explicitly
  /// instead of relying on the column default.
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

  /// Batch 5d — shares another Wisp user's profile as a message. Per
  /// PRD.md section 7, no caption/upload involved: just a `type:
  /// 'contact'` row pointing at `shared_contact_id`, exactly as
  /// ERD.md already models it.
  Future<void> sendContactMessage({
    required String conversationId,
    required String senderId,
    required String sharedContactId,
  }) async {
    try {
      await _client.from('messages').insert({
        'conversation_id': conversationId,
        'sender_id': senderId,
        'type': 'contact',
        'shared_contact_id': sharedContactId,
      });
    } on PostgrestException catch (e) {
      throw SupabaseFailure(e.message);
    }
  }

  /// Batch 5e-i — shares a single current-location pin. Live location
  /// ('location_live', `is_live_location`, `live_location_expires_at`)
  /// lands in Batch 5e-ii — deliberately not touched here.
  Future<void> sendLocationMessage({
    required String conversationId,
    required String senderId,
    required double lat,
    required double lng,
  }) async {
    try {
      await _client.from('messages').insert({
        'conversation_id': conversationId,
        'sender_id': senderId,
        'type': 'location_current',
        'location_lat': lat,
        'location_lng': lng,
      });
    } on PostgrestException catch (e) {
      throw SupabaseFailure(e.message);
    }
  }

  /// Batch 5e-ii — starts a live-location share: a 'location_live' row
  /// with `is_live_location` true and `live_location_expires_at` set.
  /// [messageId] is client-generated (uuid) so later position updates
  /// and early-stop calls can target this exact row — same reasoning
  /// as `sendMediaMessage`'s client-generated id.
  Future<void> sendLiveLocationMessage({
    required String messageId,
    required String conversationId,
    required String senderId,
    required double lat,
    required double lng,
    required DateTime expiresAt,
  }) async {
    try {
      await _client.from('messages').insert({
        'id': messageId,
        'conversation_id': conversationId,
        'sender_id': senderId,
        'type': 'location_live',
        'location_lat': lat,
        'location_lng': lng,
        'is_live_location': true,
        'live_location_expires_at': expiresAt.toIso8601String(),
      });
    } on PostgrestException catch (e) {
      throw SupabaseFailure(e.message);
    }
  }

  /// Updates the pin on an existing live-location message as the
  /// sender's position changes. Requires `messages_update_own` RLS
  /// (see migration note above).
  Future<void> updateLiveLocationPin({
    required String messageId,
    required double lat,
    required double lng,
  }) async {
    try {
      await _client.from('messages').update(
          {'location_lat': lat, 'location_lng': lng}).eq('id', messageId);
    } on PostgrestException catch (e) {
      throw SupabaseFailure(e.message);
    }
  }

  /// Lets the sender end a share early by setting the expiry to now —
  /// every viewer's client-side expiry check (5e-i decision #4) then
  /// flips it to "ended" on the next read, no separate 'stopped'
  /// state needed in ERD.md.
  Future<void> endLiveLocationEarly(String messageId) async {
    try {
      await _client.from('messages').update({
        'live_location_expires_at': DateTime.now().toIso8601String()
      }).eq('id', messageId);
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
