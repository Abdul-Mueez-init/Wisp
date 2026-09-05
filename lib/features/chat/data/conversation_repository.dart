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
  /// with the other participant (direct chats), its most recent message,
  /// and its unread count.
  ///
  /// The chat list is refreshed by realtime events, so this path must not
  /// multiply work by opening a separate member and unread query for every
  /// conversation. The member/profile lookup and unread-count lookup are
  /// batched once for the whole list. The latest-message lookup remains one
  /// bounded query per conversation because PostgREST cannot safely express
  /// "latest row per conversation" with the current schema and no RPC.
  ///
  /// This preserves the existing data contract and sorting while reducing
  /// the list refresh from roughly `1 + 3C` requests to `2 + C`, where `C`
  /// is the number of conversations. The returned rows are still filtered
  /// by the same RLS policies as before.
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
      if (conversations.isEmpty) return const [];

      final conversationIds = conversations.map((c) => c.id).toList();
      final results = await Future.wait<dynamic>([
        _fetchDirectProfilesByConversation(
          conversationIds: conversationIds,
          myId: myId,
        ),
        _fetchUnreadCountsByConversation(
          conversationIds: conversationIds,
          myId: myId,
        ),
      ]);

      final profilesByConversation = results[0] as Map<String, Profile?>;
      final unreadCounts = results[1] as Map<String, int>;

      final summaries = await Future.wait(conversations.map((conversation) {
        return _fetchSummary(
          conversation: conversation,
          otherProfile: profilesByConversation[conversation.id],
          unreadCount: unreadCounts[conversation.id] ?? 0,
        );
      }));

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

  /// Fetches every member/profile row for the list's conversations once,
  /// then keeps the member that is not [myId] for direct conversations.
  /// Groups intentionally remain null, matching the previous behavior.
  Future<Map<String, Profile?>> _fetchDirectProfilesByConversation({
    required List<String> conversationIds,
    required String myId,
  }) async {
    final rows = await _client
        .from('conversation_members')
        .select('conversation_id, user_id, profiles!inner(*)')
        .inFilter('conversation_id', conversationIds);

    final profiles = <String, Profile?>{};
    for (final raw in rows as List) {
      final row = raw as Map<String, dynamic>;
      final conversationId = row['conversation_id'] as String;
      final userId = row['user_id'] as String;
      if (userId == myId) continue;
      final profileRow = row['profiles'];
      if (profileRow is Map<String, dynamic>) {
        profiles[conversationId] = Profile.fromJson(profileRow);
      }
    }
    return profiles;
  }

  /// Fetches unread candidates for all conversations in one request. The
  /// per-message semantics are intentionally unchanged: an incoming message
  /// is unread unless this user has a related status row with `read` status.
  Future<Map<String, int>> _fetchUnreadCountsByConversation({
    required List<String> conversationIds,
    required String myId,
  }) async {
    final rows = await _client
        .from('messages')
        .select('conversation_id, message_status(user_id, status)')
        .inFilter('conversation_id', conversationIds)
        .neq('sender_id', myId);

    final unreadCounts = <String, int>{};
    for (final raw in rows as List) {
      final row = raw as Map<String, dynamic>;
      final conversationId = row['conversation_id'] as String;
      final statusRows = (row['message_status'] as List?) ?? const [];
      final isReadByMe = statusRows.any((s) {
        final status = s as Map<String, dynamic>;
        return status['user_id'] == myId && status['status'] == 'read';
      });
      if (!isReadByMe) {
        unreadCounts[conversationId] = (unreadCounts[conversationId] ?? 0) + 1;
      }
    }
    return unreadCounts;
  }

  Future<ConversationSummary> _fetchSummary({
    required Conversation conversation,
    required Profile? otherProfile,
    required int unreadCount,
  }) async {
    final lastMessageRow = await _client
        .from('messages')
        .select()
        .eq('conversation_id', conversation.id)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    return ConversationSummary(
      conversation: conversation,
      otherProfile: conversation.isDirect ? otherProfile : null,
      lastMessage:
          lastMessageRow != null ? Message.fromJson(lastMessageRow) : null,
      unreadCount: unreadCount,
    );
  }
}
