import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/failure.dart';
import '../../../models/conversation.dart';
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
    // 1. All direct conversations I'm currently a member of.
    final myRows = await _client
        .from('conversation_members')
        .select('conversation_id, conversations!inner(type)')
        .eq('user_id', myId)
        .eq('conversations.type', 'direct');

    final myConversationIds =
        (myRows as List).map((r) => r['conversation_id'] as String).toList();
    if (myConversationIds.isEmpty) return null;

    // 2. Of those, is the other user also a member of any of them?
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

    // Direct chats have no admin concept — ERD.md's admin/member role
    // only governs group member management (PRD.md section 6) — so
    // both participants get 'member' here.
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
}
