import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/supabase_config.dart';
import '../../../core/errors/failure.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/conversation_repository.dart';
import '../../../models/conversation.dart';

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
