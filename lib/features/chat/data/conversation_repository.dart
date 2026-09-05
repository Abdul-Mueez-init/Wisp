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
  /// multiply work by pulling unbounded historical message tables.
  /// Direct member profile lookup is batched once for the whole list.
  /// Latest message and unread status are resolved together per conversation
  /// in a bounded manner: if the newest message is already read or was sent
  /// by [myId], unread count is zero immediately without scanning history.
  /// Only active conversations with unread incoming messages scan recent
  /// unread candidates (bounded to 50), breaking at the first read row.
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
      final profilesByConversation = await _fetchDirectProfilesByConversation(
        conversationIds: conversationIds,
        myId: myId,
      );

      final summaries = await Future.wait(conversations.map((conversation) {
        return _fetchSummary(
          conversation: conversation,
          otherProfile: profilesByConversation[conversation.id],
          myId: myId,
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

  Future<ConversationSummary> _fetchSummary({
    required Conversation conversation,
    required Profile? otherProfile,
    required String myId,
  }) async {
    final lastMessageRow = await _client
        .from('messages')
        .select('*, message_status(user_id, status)')
        .eq('conversation_id', conversation.id)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    Message? lastMessage;
    var unreadCount = 0;

    if (lastMessageRow != null) {
      lastMessage = Message.fromJson(lastMessageRow);
      final statusRows =
          (lastMessageRow['message_status'] as List?) ?? const [];
      final isFromMe = lastMessage.senderId == myId;
      final isReadByMe = statusRows.any((s) {
        final status = s as Map<String, dynamic>;
        return status['user_id'] == myId && status['status'] == 'read';
      });

      // If the latest message is sent by me or already read by me, unread count is 0.
      // Otherwise, scan recent unread messages in this conversation.
      if (!isFromMe && !isReadByMe) {
        unreadCount = await _countUnreadForConversation(
          conversationId: conversation.id,
          myId: myId,
        );
      }
    }

    return ConversationSummary(
      conversation: conversation,
      otherProfile: conversation.isDirect ? otherProfile : null,
      lastMessage: lastMessage,
      unreadCount: unreadCount,
    );
  }

  /// Counts unread incoming messages for a single conversation, scanning newest
  /// to oldest with a bounded limit of 50. Stops as soon as a read message is encountered.
  Future<int> _countUnreadForConversation({
    required String conversationId,
    required String myId,
  }) async {
    final rows = await _client
        .from('messages')
        .select('id, created_at, message_status(user_id, status)')
        .eq('conversation_id', conversationId)
        .neq('sender_id', myId)
        .order('created_at', ascending: false)
        .limit(50);

    var count = 0;
    for (final raw in rows as List) {
      final row = raw as Map<String, dynamic>;
      final statusRows = (row['message_status'] as List?) ?? const [];
      final isRead = statusRows.any((s) {
        final status = s as Map<String, dynamic>;
        return status['user_id'] == myId && status['status'] == 'read';
      });
      if (isRead) {
        // Chronological invariant: once an already-read message is reached,
        // all older messages are also read.
        break;
      }
      count++;
    }
    return count;
  }
}
