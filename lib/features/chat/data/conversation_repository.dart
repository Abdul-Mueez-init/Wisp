import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/failure.dart';
import '../../../models/conversation.dart';
import '../../../models/conversation_summary.dart';
import '../../../models/message.dart';
import '../../../models/profile.dart';

/// Conversation creation/lookup per PRD.md section 5: "Starting a chat =
/// search username → tap → open/create 1-on-1 conversation." All
/// `conversations`/`conversation_members` writes for this flow go
/// through here (rules.md Rule 8 pattern extended to the chat domain).
/// Group creation (Phase 3) is out of scope for this repository.
class ConversationRepository {
  ConversationRepository(this._client);
  final SupabaseClient _client;

  /// The other participant of a direct conversation — used to render
  /// the chat detail app bar (name/avatar) when it wasn't already
  /// passed in via navigation `extra`.
  Future<Profile?> getOtherDirectMember({
    required String conversationId,
    required String myId,
  }) async {
    try {
      final row = await _client
          .from('conversation_members')
          .select('profiles!inner(*)')
          .eq('conversation_id', conversationId)
          .neq('user_id', myId)
          .limit(1)
          .maybeSingle();
      if (row == null) return null;
      return Profile.fromJson(row['profiles'] as Map<String, dynamic>);
    } on PostgrestException catch (e) {
      throw SupabaseFailure(e.message);
    }
  }

  /// Finds the existing direct conversation between [myId] and
  /// [otherId], or creates one if none exists yet.
  Future<Conversation> findOrCreateDirectConversation({
    required String myId,
    required String otherId,
  }) async {
    try {
      final existing = await _findExistingDirect(myId, otherId);
      if (existing != null) return existing;
      return await _createDirect(myId, otherId);
    } on PostgrestException catch (e) {
      throw SupabaseFailure(e.message);
    }
  }

  Future<Conversation?> _findExistingDirect(
    String myId,
    String otherId,
  ) async {
    final myRows = await _client
        .from('conversation_members')
        .select('conversation_id, conversations!inner(type)')
        .eq('user_id', myId)
        .eq('conversations.type', 'direct');

    final myConversationIds =
        (myRows as List).map((r) => r['conversation_id'] as String).toList();
    if (myConversationIds.isEmpty) return null;

    final match = await _client
        .from('conversation_members')
        .select('conversations!inner(*)')
        .eq('user_id', otherId)
        .inFilter('conversation_id', myConversationIds)
        .limit(1)
        .maybeSingle();

    if (match == null) return null;
    return Conversation.fromJson(
      match['conversations'] as Map<String, dynamic>,
    );
  }

  Future<Conversation> _createDirect(String myId, String otherId) async {
    final convRow = await _client
        .from('conversations')
        .insert({'type': 'direct', 'created_by': myId})
        .select()
        .single();

    final conversationId = convRow['id'] as String;

    await _client.from('conversation_members').insert([
      {'conversation_id': conversationId, 'user_id': myId, 'role': 'member'},
      {
        'conversation_id': conversationId,
        'user_id': otherId,
        'role': 'member',
      },
    ]);

    return Conversation.fromJson(convRow);
  }

  /// Fetches a single conversation row by id — used by the chat detail
  /// screen to resolve a group's name/type when it wasn't passed in via
  /// navigation `extra` (Phase 3).
  Future<Conversation?> getConversation(String conversationId) async {
    try {
      final row = await _client
          .from('conversations')
          .select()
          .eq('id', conversationId)
          .maybeSingle();
      if (row == null) return null;
      return Conversation.fromJson(row);
    } on PostgrestException catch (e) {
      throw SupabaseFailure(e.message);
    }
  }

  /// Fetches every conversation [myId] is a member of, each paired
  /// with the other participant (direct chats) and its most recent
  /// message (chat list preview, Batch 6b). N+1 queries — one extra
  /// round trip per conversation for its last message — acceptable at
  /// this app's demo scale, same reasoning `MediaRepository
  /// .resolveFileInfo`'s extra `list()` call already uses. PostgREST
  /// embedding doesn't cleanly support order+limit-1 on a nested
  /// resource, so this stays a plain two-step fetch instead of a
  /// fragile embedded query.
  Future<List<ConversationSummary>> fetchMyConversationSummaries(
    String myId,
  ) async {
    try {
      final memberRows = await _client
          .from('conversation_members')
          .select('conversations!inner(*)')
          .eq('user_id', myId);

      final conversations = (memberRows as List)
          .map((r) =>
              Conversation.fromJson(r['conversations'] as Map<String, dynamic>))
          .toList();

      final summaries = <ConversationSummary>[];
      for (final conversation in conversations) {
        Profile? otherProfile;
        if (conversation.isDirect) {
          otherProfile = await getOtherDirectMember(
            conversationId: conversation.id,
            myId: myId,
          );
        }

        final lastMessageRow = await _client
            .from('messages')
            .select()
            .eq('conversation_id', conversation.id)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();

        summaries.add(ConversationSummary(
          conversation: conversation,
          otherProfile: otherProfile,
          lastMessage:
              lastMessageRow != null ? Message.fromJson(lastMessageRow) : null,
        ));
      }

      // Most recently active conversation first — falls back to
      // `conversations.created_at` for a chat with no messages yet.
      summaries.sort((a, b) {
        final aTime = a.lastMessage?.createdAt ?? a.conversation.createdAt;
        final bTime = b.lastMessage?.createdAt ?? b.conversation.createdAt;
        return bTime.compareTo(aTime);
      });

      return summaries;
    } on PostgrestException catch (e) {
      throw SupabaseFailure(e.message);
    }
  }
}
