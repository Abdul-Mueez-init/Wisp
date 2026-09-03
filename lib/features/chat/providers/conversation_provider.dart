import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../config/supabase_config.dart';
import '../../../core/errors/failure.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/conversation_repository.dart';
import '../../../models/conversation.dart';
import '../../../models/conversation_summary.dart';

final conversationRepositoryProvider = Provider<ConversationRepository>((ref) {
  return ConversationRepository(SupabaseConfig.client);
});

/// One-off action: open a 1-on-1 chat from a search result. Returns the
/// resulting conversation id on success so the UI can navigate to it.
/// Per architecture.md, this action logic lives in a Notifier, not in
/// the search screen widget.
class StartConversationController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<String?> startDirectConversationWith(String otherUserId) async {
    final myId = ref.read(currentSessionProvider)?.user.id;
    if (myId == null) {
      state = AsyncError(
        const AuthFailure('No authenticated session found.'),
        StackTrace.current,
      );
      return null;
    }

    state = const AsyncLoading();
    String? conversationId;
    state = await AsyncValue.guard(() async {
      final conversation = await ref
          .read(conversationRepositoryProvider)
          .findOrCreateDirectConversation(myId: myId, otherId: otherUserId);
      conversationId = conversation.id;
    });
    return conversationId;
  }

  /// Phase 8 — opens (finding or creating) the user's reserved AI-DM
  /// conversation. Same `AsyncNotifier<void>` / return-the-id shape as
  /// [startDirectConversationWith] above, deliberately reusing this
  /// controller rather than adding a parallel one, since both actions
  /// are "resolve a direct conversation id, then navigate."
  Future<String?> openAiConversation() async {
    final myId = ref.read(currentSessionProvider)?.user.id;
    if (myId == null) {
      state = AsyncError(
        const AuthFailure('No authenticated session found.'),
        StackTrace.current,
      );
      return null;
    }

    state = const AsyncLoading();
    String? conversationId;

    state = await AsyncValue.guard(() async {
      final conversation = await ref
          .read(conversationRepositoryProvider)
          .findOrCreateAiConversation(myId);
      conversationId = conversation.id;
    });
    return conversationId;
  }
}

final startConversationControllerProvider =
    AsyncNotifierProvider<StartConversationController, void>(
  StartConversationController.new,
);

/// Resolves a conversation's own row (name, type, etc.) — used when the
/// chat detail screen wasn't handed one via navigation `extra`.
final conversationByIdProvider =
    FutureProvider.family<Conversation?, String>((ref, conversationId) {
  return ref
      .read(conversationRepositoryProvider)
      .getConversation(conversationId);
});

/// Chat list data source (Batch 6b, made realtime in Phase 2 per
/// wisp_fixes_handoff.md).
///
/// PostgREST embedding still can't cleanly express "conversations +
/// last message" as a single realtime-streamable query (same reasoning
/// `activeStoryGroupsProvider` uses), so this isn't a direct
/// `.stream()` wrapper around one table. Instead it re-runs
/// [ConversationRepository.fetchMyConversationSummaries] (now
/// parallelized, Finding D) whenever something relevant changes, via
/// two Realtime channels:
///  - `messages` inserts/updates, unfiltered — a new message anywhere,
///    or an update (e.g. Phase 7 translation landing) that could change
///    a preview.
///  - `conversation_members` inserts, unfiltered — a brand-new
///    conversation (direct or group) this user was just added to,
///    which wouldn't have a `messages` row yet to trigger the first
///    channel.
/// Both are subscribed without a server-side filter because Realtime's
/// `PostgresChangeFilter` only supports a single `eq`, and what's
/// needed here is "any row this user's own RLS SELECT policy would let
/// them see" — which is exactly what Postgres Changes already enforces
/// per-subscriber given `messages_select_member` /
/// `members_select_own_conversations` (verified live, Phase 1). A
/// change this user isn't allowed to see never reaches this channel in
/// the first place.
/// Rapid-fire changes (e.g. several `message_status` reads landing at
/// once) are coalesced with a short debounce so this doesn't refetch
/// once per event.
///
/// This also closes the previously-flagged "chat list doesn't
/// auto-reorder on a new message elsewhere in the app" limitation —
/// any qualifying event now triggers a fresh, correctly-sorted fetch.
final myConversationSummariesProvider =
    StreamProvider.autoDispose<List<ConversationSummary>>((ref) {
  final myId = ref.watch(currentSessionProvider)?.user.id;
  if (myId == null) return Stream.value(const []);

  final repo = ref.watch(conversationRepositoryProvider);
  final controller = StreamController<List<ConversationSummary>>();
  Timer? debounce;

  Future<void> refresh() async {
    try {
      final summaries = await repo.fetchMyConversationSummaries(myId);
      if (!controller.isClosed) controller.add(summaries);
    } catch (e, st) {
      if (!controller.isClosed) controller.addError(e, st);
    }
  }

  void scheduleRefresh() {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 300), refresh);
  }

  // Initial load — fires immediately, not debounced.
  unawaited(refresh());

  final messagesChannel = SupabaseConfig.client
      .channel('chat-list-messages-$myId')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'messages',
        callback: (_) => scheduleRefresh(),
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'messages',
        callback: (_) => scheduleRefresh(),
      )
      .subscribe();

  final membersChannel = SupabaseConfig.client
      .channel('chat-list-members-$myId')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'conversation_members',
        callback: (_) => scheduleRefresh(),
      )
      .subscribe();

  // BUGFIX (wisp_fixes.txt: unread badge "doesn't remove immediately,
  // only after refresh") — `markRead()` (chat_detail_screen.dart's
  // `_syncReadReceipts`) writes to `message_status`, not `messages`,
  // so the two channels above never fired when a chat got read. Third
  // channel, same pattern: any `message_status` row update for rows
  // belonging to *this* user (the recipient whose read-state actually
  // drives `ConversationSummary.unreadCount`) schedules the same
  // debounced refetch. Filtered with `eq` on `user_id` — unlike the
  // other two channels, `message_status_select_own`'s RLS shape is a
  // single-column equality, so a server-side filter is both possible
  // and cheaper than relying on RLS alone here.
  final readReceiptsChannel = SupabaseConfig.client
      .channel('chat-list-read-receipts-$myId')
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'message_status',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id',
          value: myId,
        ),
        callback: (_) => scheduleRefresh(),
      )
      .subscribe();

  ref.onDispose(() {
    debounce?.cancel();
    SupabaseConfig.client.removeChannel(messagesChannel);
    SupabaseConfig.client.removeChannel(membersChannel);
    SupabaseConfig.client.removeChannel(readReceiptsChannel);
    controller.close();
  });

  return controller.stream;
});
