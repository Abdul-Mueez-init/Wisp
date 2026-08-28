import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// Chat list data source (Batch 6b). FutureProvider, not
/// StreamProvider — same join reasoning as `activeStoryGroupsProvider`
/// (PostgREST embedding can't cleanly express "conversations + last
/// message" as a single realtime-streamable query). Invalidated via
/// pull-to-refresh on the chat list screen.
///
/// Known limitation, flagged rather than silently accepted: this list
/// does NOT auto-reorder the instant a new message arrives elsewhere in
/// the app — only on refresh/re-navigation. A realtime-perfect version
/// would need a `.stream()`-based provider per conversation feeding a
/// combined view, which is meaningfully more plumbing; deferred rather
/// than built silently, matching Rule 1.
final myConversationSummariesProvider =
    FutureProvider<List<ConversationSummary>>((ref) async {
  final myId = ref.watch(currentSessionProvider)?.user.id;
  if (myId == null) return const [];
  return ref
      .read(conversationRepositoryProvider)
      .fetchMyConversationSummaries(myId);
});
