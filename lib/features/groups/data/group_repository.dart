import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/failure.dart';
import '../../../models/conversation.dart';
import '../../../models/conversation_member.dart';

/// Group-only `conversations`/`conversation_members` reads and writes
/// (rules.md Rule 8 pattern extended to the chat domain). 1-on-1 logic
/// stays in ConversationRepository — this is Phase 3 scope only.
class GroupRepository {
  GroupRepository(this._client);
  final SupabaseClient _client;

  /// Per PRD.md section 6: "Any user can create a group and add
  /// members... Only the group creator/admin can add/remove members
  /// after creation." [creatorId] is inserted as 'admin', everyone in
  /// [memberIds] as 'member'.
  Future<Conversation> createGroup({
    required String creatorId,
    required String name,
    required List<String> memberIds,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw const ValidationFailure('Group name cannot be empty.');
    }
    if (memberIds.isEmpty) {
      throw const ValidationFailure('Add at least one member to the group.');
    }

    try {
      final convRow = await _client
          .from('conversations')
          .insert({
            'type': 'group',
            'name': trimmedName,
            'created_by': creatorId,
          })
          .select()
          .single();

      final conversationId = convRow['id'] as String;

      await _client.from('conversation_members').insert([
        {
          'conversation_id': conversationId,
          'user_id': creatorId,
          'role': 'admin',
        },
        ...memberIds.map(
          (id) => {
            'conversation_id': conversationId,
            'user_id': id,
            'role': 'member',
          },
        ),
      ]);

      return Conversation.fromJson(convRow);
    } on PostgrestException catch (e) {
      throw SupabaseFailure(e.message);
    }
  }

  /// Full membership list with profiles joined, for the group members
  /// screen. A one-off fetch (not a stream) — supabase_flutter's
  /// `.stream()` doesn't support this join (same limitation noted in
  /// ConversationRepository.getOtherDirectMember). Callers invalidate
  /// the wrapping provider after add/remove actions to refresh.
  Future<List<ConversationMember>> fetchMembers(String conversationId) async {
    try {
      final rows = await _client
          .from('conversation_members')
          .select('id, conversation_id, role, joined_at, profiles!inner(*)')
          .eq('conversation_id', conversationId)
          .order('joined_at', ascending: true);
      return (rows as List)
          .map((r) =>
              ConversationMember.fromJoinedJson(r as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw SupabaseFailure(e.message);
    }
  }

  /// This user's role in [conversationId], or null if not a member.
  /// Gates admin-only add/remove UI per PRD.md section 6.
  Future<String?> myRole({
    required String conversationId,
    required String userId,
  }) async {
    try {
      final row = await _client
          .from('conversation_members')
          .select('role')
          .eq('conversation_id', conversationId)
          .eq('user_id', userId)
          .maybeSingle();
      return row?['role'] as String?;
    } on PostgrestException catch (e) {
      throw SupabaseFailure(e.message);
    }
  }

  /// Admin-only per PRD.md — enforced client-side here and server-side
  /// by the `members_insert_creator_or_admin` RLS policy.
  Future<void> addMembers({
    required String conversationId,
    required List<String> userIds,
  }) async {
    if (userIds.isEmpty) return;
    try {
      await _client.from('conversation_members').insert(
            userIds
                .map((id) => {
                      'conversation_id': conversationId,
                      'user_id': id,
                      'role': 'member',
                    })
                .toList(),
          );
    } on PostgrestException catch (e) {
      throw SupabaseFailure(e.message);
    }
  }

  /// Admin-only per PRD.md — enforced client-side here and server-side
  /// by the `members_delete_admin` RLS policy.
  Future<void> removeMember({
    required String conversationId,
    required String userId,
  }) async {
    try {
      await _client
          .from('conversation_members')
          .delete()
          .eq('conversation_id', conversationId)
          .eq('user_id', userId);
    } on PostgrestException catch (e) {
      throw SupabaseFailure(e.message);
    }
  }
}
