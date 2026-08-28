// lib/features/ai_agent/providers/ai_agent_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/supabase_config.dart';
import '../../auth/providers/auth_provider.dart';
import '../../chat/data/message_repository.dart';
import '../../profile/providers/profile_provider.dart';
import '../data/ai_agent_repository.dart';

final aiAgentRepositoryProvider = Provider<AiAgentRepository>((ref) {
  return const AiAgentRepository();
});

/// A second `Provider<MessageRepository>`, distinct from
/// `chat/providers/message_provider.dart`'s `messageRepositoryProvider`
/// — deliberately. `SendMessageController` (chat) needs to import this
/// file to trigger the agent on send/@mention, so the reverse import
/// (this file depending on `message_provider.dart`) would be circular.
/// `MessageRepository` holds no state beyond the shared
/// `SupabaseConfig.client` singleton, so this isn't a second source of
/// truth in practice — same underlying client either way.
final _aiAgentMessageRepositoryProvider = Provider<MessageRepository>((ref) {
  return MessageRepository(SupabaseConfig.client);
});

/// Whether the agent is currently composing a reply in a given
/// conversation — watched by `ChatDetailScreen` to show a lightweight
/// "Wisp is typing…" state, matching PRD.md's "must feel instant"
/// realtime principle even though this particular signal is local
/// (not broadcast via `typing_status` — nobody else needs to see it).
final aiAgentThinkingProvider =
    StateProvider.family<bool, String>((ref, conversationId) => false);

/// Orchestrates AI Feature 2 end to end: pull recent history, resolve
/// human sender display names, ask `AiAgentRepository` for a reply,
/// insert it back into the same conversation as an `is_ai_message`
/// row. Triggered from `SendMessageController.sendText` — the Gemini/
/// Groq call itself still only ever happens through `AiConfig`
/// (rules.md Rule 8); this controller just owns *when* to make it.
class AiAgentController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  static const _historyLimit = 20;

  /// [forceRespond] is true for the dedicated AI-DM conversation
  /// (PRD.md's "direct-message the AI like a regular contact" path —
  /// `ConversationRepository.findOrCreateAiConversation`, every
  /// message there gets a reply). Otherwise this only fires on an
  /// explicit "@wisp" mention (the other PRD.md access path), so
  /// ordinary human-to-human chat is never interrupted uninvited.
  Future<void> maybeRespond({
    required String conversationId,
    required String triggerText,
    bool forceRespond = false,
  }) async {
    if (!forceRespond && !AiAgentRepository.mentionsAgent(triggerText)) {
      return;
    }

    final myId = ref.read(currentSessionProvider)?.user.id;
    final thinking = ref.read(aiAgentThinkingProvider(conversationId).notifier);
    thinking.state = true;
    try {
      final repo = ref.read(_aiAgentMessageRepositoryProvider);
      final history = await repo.fetchRecentMessages(
        conversationId: conversationId,
        limit: _historyLimit,
      );

      final otherSenderIds = history
          .map((m) => m.senderId)
          .whereType<String>()
          .where((id) => id != myId)
          .toSet();
      final labels = otherSenderIds.isEmpty
          ? const <String, String>{}
          : await ref
              .read(profileRepositoryProvider)
              .fetchDisplayLabels(otherSenderIds);

      final reply = await ref.read(aiAgentRepositoryProvider).generateReply(
            history: history,
            myId: myId,
            senderLabels: labels,
          );
      if (reply.isEmpty) return;

      await repo.sendAiMessage(
        conversationId: conversationId,
        content: reply,
      );
    } catch (_) {
      // Best-effort — same "never fail the human's own send" reasoning
      // as `SendMessageController._translateIfDirect`. A failed agent
      // reply is silently dropped, not surfaced as an error on the
      // message the user actually sent.
    } finally {
      thinking.state = false;
    }
  }
}

final aiAgentControllerProvider =
    AsyncNotifierProvider<AiAgentController, void>(AiAgentController.new);
