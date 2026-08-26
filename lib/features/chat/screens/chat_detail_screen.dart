import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/message.dart';
import '../../../models/profile.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/message_provider.dart';
import '../widgets/chat_input_bar.dart';
import '../widgets/message_bubble.dart';

/// Real Phase 2 chat detail screen — replaces the router's temporary
/// placeholder. Built off the Stitch `chat_detail_1_on_1` export.
class ChatDetailScreen extends ConsumerStatefulWidget {
  const ChatDetailScreen({
    super.key,
    required this.conversationId,
    this.otherProfile,
  });

  final String conversationId;
  final Profile? otherProfile;

  @override
  ConsumerState<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends ConsumerState<ChatDetailScreen> {
  @override
  void initState() {
    super.initState();
    // Fire-and-forget: syncing read receipts is a side effect, not
    // shared app state, so calling the repository directly here (rather
    // than routing it through a watched provider) is appropriate.
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncReadReceipts());
  }

  Future<void> _syncReadReceipts() async {
    final myId = ref.read(currentSessionProvider)?.user.id;
    if (myId == null) return;
    final repo = ref.read(messageRepositoryProvider);
    // Sequenced deliberately: 'delivered' then 'read' so the row
    // genuinely passes through both states (see context.md note on why
    // they currently land back-to-back until a chat-list-level listener
    // exists).
    await repo.markDelivered(conversationId: widget.conversationId, myId: myId);
    await repo.markRead(conversationId: widget.conversationId, myId: myId);
  }

  @override
  Widget build(BuildContext context) {
    final myId = ref.watch(currentSessionProvider)?.user.id;
    final messagesAsync =
        ref.watch(messagesStreamProvider(widget.conversationId));
    final statusesAsync = ref.watch(messageStatusesStreamProvider);
    final otherProfileAsync = widget.otherProfile != null
        ? null
        : ref.watch(otherDirectMemberProvider(widget.conversationId));
    final sending = ref.watch(sendMessageControllerProvider).isLoading;

    // Re-sync read receipts whenever new messages land while the screen
    // is open (safe: this writes to message_status, not messages, so it
    // can't feed back into the messages stream it's reacting to).
    ref.listen(messagesStreamProvider(widget.conversationId), (prev, next) {
      if (next.hasValue) _syncReadReceipts();
    });

    final displayProfile = widget.otherProfile ?? (otherProfileAsync?.value);

    return Scaffold(
      backgroundColor: AppColors.backgroundBase,
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.surfaceContainerHigh,
              child: Text(
                (displayProfile?.displayName?.isNotEmpty == true
                        ? displayProfile!.displayName!
                        : displayProfile?.username ?? '?')
                    .substring(0, 1)
                    .toUpperCase(),
                style: const TextStyle(color: AppColors.primary),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                displayProfile != null ? '@${displayProfile.username}' : 'Chat',
                style: Theme.of(context).textTheme.titleMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: messagesAsync.when(
              data: (messages) {
                if (messages.isEmpty) {
                  return Center(
                    child: Text(
                      'Say hi 👋',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  );
                }
                final reversed = messages.reversed.toList();
                final statuses = statusesAsync.value ?? const [];

                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.pageMargin,
                    vertical: 12,
                  ),
                  itemCount: reversed.length,
                  itemBuilder: (context, index) {
                    final Message message = reversed[index];
                    final isMine = message.senderId == myId;
                    String? status;
                    if (isMine) {
                      final match = statuses.where(
                        (s) => s.messageId == message.id,
                      );
                      if (match.isNotEmpty) status = match.first.status;
                    }
                    return MessageBubble(
                      message: message,
                      isMine: isMine,
                      status: status,
                    );
                  },
                );
              },
              loading: () => const Center(
                  child: CircularProgressIndicator(strokeWidth: 2)),
              error: (e, _) => Center(
                child: Text(
                  'Could not load messages.\n$e',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
          ),
          ChatInputBar(
            sending: sending,
            onSend: (text) => ref
                .read(sendMessageControllerProvider.notifier)
                .sendText(conversationId: widget.conversationId, content: text),
          ),
        ],
      ),
    );
  }
}
