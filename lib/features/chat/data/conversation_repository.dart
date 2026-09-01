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

  /// Phase 8 — the AI Feature 2 "direct-message the agent like a
  /// regular contact" entry point (PRD.md §10). Deliberately NOT a new
  /// `conversations.type` value (no schema change, per rules.md Rule
  /// 7): instead this is an ordinary `type: 'direct'` conversation
  /// whose ONLY `conversation_members` row is the user themself.
  /// [_createDirect] above always inserts *both* members together for
  /// a real human-to-human direct chat, so a single-member direct
  /// conversation can only ever be this reserved AI thread — that
  /// invariant is what lets the rest of the app (chat list tile, chat
  /// detail screen) treat "is this the AI conversation?" as derived
  /// data instead of a new column.
  Future<Conversation> findOrCreateAiConversation(String myId) async {
    try {
      final existing = await _findExistingAiConversation(myId);
      if (existing != null) return existing;

      final convRow = await _client
          .from('conversations')
          .insert({'type': 'direct', 'created_by': myId})
          .select()
          .single();
      final conversationId = convRow['id'] as String;

      await _client.from('conversation_members').insert({
        'conversation_id': conversationId,
        'user_id': myId,
        'role': 'member',
      });

      return Conversation.fromJson(convRow);
    } on PostgrestException catch (e) {
      throw SupabaseFailure(e.message);
    }
  }

  Future<Conversation?> _findExistingAiConversation(String myId) async {
    final myRows = await _client
        .from('conversation_members')
        .select('conversation_id, conversations!inner(*)')
        .eq('user_id', myId)
        .eq('conversations.type', 'direct');

    final myDirectIds =
        (myRows as List).map((r) => r['conversation_id'] as String).toList();
    if (myDirectIds.isEmpty) return null;

    // One query for every member row across all of my direct
    // conversations, then group client-side to find the one with
    // exactly one member — PostgREST can't express a "having count =
    // 1" filter directly, and this avoids an extra round trip per
    // conversation on top of it.
    final allMemberRows = await _client
        .from('conversation_members')
        .select('conversation_id')
        .inFilter('conversation_id', myDirectIds);

    final counts = <String, int>{};
    for (final row in allMemberRows as List) {
      final id = row['conversation_id'] as String;
      counts[id] = (counts[id] ?? 0) + 1;
    }

    final aiConversationId = counts.entries
        .firstWhere((e) => e.value == 1, orElse: () => const MapEntry('', 0))
        .key;
    if (aiConversationId.isEmpty) return null;

    final match =
        myRows.firstWhere((r) => r['conversation_id'] == aiConversationId);
    return Conversation.fromJson(
      match['conversations'] as Map<String, dynamic>,
    );
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
  /// message (chat list preview, Batch 6b).
  ///
  /// Phase 2 fix (wisp_fixes_handoff.md, Finding D): this used to run
  /// two sequential `await`ed queries per conversation inside a `for`
  /// loop — one round trip at a time, so 10 chats meant 20+ serial
  /// round trips end to end. Still N+1 in *query count* (PostgREST
  /// embedding doesn't cleanly support order+limit-1 on a nested
  /// resource, so a single combined query isn't practical here), but
  /// every conversation's pair of queries — and every conversation's
  /// pair relative to every other conversation's — now fires
  /// concurrently via [Future.wait], so wall-clock time is roughly one
  /// round trip's worth regardless of chat count, not one per chat.
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

      final summaries = await Future.wait(conversations.map(
        (conversation) => _fetchSummary(conversation: conversation, myId: myId),
      ));

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

  /// One conversation's pair of lookups (other member + last message),
  /// run concurrently with each other via [Future.wait] — the unit of
  /// work [fetchMyConversationSummaries] then fans out across all of a
  /// user's conversations at once.
  Future<ConversationSummary> _fetchSummary({
    required Conversation conversation,
    required String myId,
  }) async {
    final results = await Future.wait<dynamic>([
      conversation.isDirect
          ? getOtherDirectMember(conversationId: conversation.id, myId: myId)
          : Future<Profile?>.value(null),
      _client
          .from('messages')
          .select()
          .eq('conversation_id', conversation.id)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle(),
    ]);

    final otherProfile = results[0] as Profile?;
    final lastMessageRow = results[1] as Map<String, dynamic>?;

    return ConversationSummary(
      conversation: conversation,
      otherProfile: otherProfile,
      lastMessage:
          lastMessageRow != null ? Message.fromJson(lastMessageRow) : null,
    );
  }
}
