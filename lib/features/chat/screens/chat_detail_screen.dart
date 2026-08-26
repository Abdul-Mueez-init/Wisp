import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/conversation.dart';
import '../../../models/message.dart';
import '../../../models/profile.dart';
import '../../auth/providers/auth_provider.dart';
import '../../groups/providers/group_provider.dart';
import '../providers/conversation_provider.dart';
import '../providers/message_provider.dart';
import '../widgets/chat_input_bar.dart';
import '../widgets/message_bubble.dart';

/// Phase 2 1-on-1 chat core, extended in Phase 3 to also render group
/// conversations (plan.md: "Group chat detail screen (reuses chat core
/// from Phase 2)") — same message stream/input, plus a group-aware app
/// bar and sender-name labels on received bubbles.
class ChatDetailScreen extends ConsumerStatefulWidget {
  const ChatDetailScreen({
    super.key,
    required this.conversationId,
    this.otherProfile,
    this.groupConversation,
  });

  final String conversationId;

  /// Passed via navigation `extra` when opening a direct chat from
  /// search results — avoids an extra fetch (Phase 2).
  final Profile? otherProfile;

  /// Passed via navigation `extra` right after creating a group — same
  /// reasoning as [otherProfile] (Phase 3).
  final Conversation? groupConversation;

  @override
  ConsumerState<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends ConsumerState<ChatDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncReadReceipts());
  }

  Future<void> _syncReadReceipts() async {
    final myId = ref.read(currentSessionProvider)?.user.id;
    if (myId == null) return;
    final repo = ref.read(messageRepositoryProvider);
    await repo.markDelivered(conversationId: widget.conversationId, myId: myId);
    await repo.markRead(conversationId: widget.conversationId, myId: myId);
  }

  @override
  Widget build(BuildContext context) {
    final myId = ref.watch(currentSessionProvider)?.user.id;
    final messagesAsync =
        ref.watch(messagesStreamProvider(widget.conversationId));
    final statusesAsync = ref.watch(messageStatusesStreamProvider);
    final sending = ref.watch(sendMessageControllerProvider).isLoading;

    // Only fetch the conversation row when we weren't handed one via
    // `extra` (e.g. a deep link straight into a group chat).
    final needsConversationFetch =
        widget.otherProfile == null && widget.groupConversation == null;
    final conversationAsync = needsConversationFetch
        ? ref.watch(conversationByIdProvider(widget.conversationId))
        : null;
    final resolvedConversation =
        widget.groupConversation ?? conversationAsync?.value;
    final isGroup = resolvedConversation?.isGroup ?? false;

    final otherProfileAsync = (!isGroup && widget.otherProfile == null)
        ? ref.watch(otherDirectMemberProvider(widget.conversationId))
        : null;
    final displayProfile = widget.otherProfile ?? otherProfileAsync?.value;

    final membersAsync =
        isGroup ? ref.watch(groupMembersProvider(widget.conversationId)) : null;
    final senderNames = <String, String>{
      for (final m in membersAsync?.value ?? const [])
        m.profile.id: m.profile.displayName?.isNotEmpty == true
            ? m.profile.displayName!
            : '@${m.profile.username}',
    };

    ref.listen(messagesStreamProvider(widget.conversationId), (prev, next) {
      if (next.hasValue) _syncReadReceipts();
    });

    return Scaffold(
      backgroundColor: AppColors.backgroundBase,
      appBar: AppBar(
        titleSpacing: 0,
        title: InkWell(
          onTap: isGroup
              ? () => context.push('/group/${widget.conversationId}/members')
              : null,
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.surfaceContainerHigh,
                child: Text(
                  _titleInitial(isGroup, resolvedConversation, displayProfile),
                  style: const TextStyle(color: AppColors.primary),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _titleText(isGroup, resolvedConversation, displayProfile),
                  style: Theme.of(context).textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isGroup)
                const Icon(Icons.chevron_right, color: AppColors.outline),
            ],
          ),
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
                      final match =
                          statuses.where((s) => s.messageId == message.id);
                      if (match.isNotEmpty) status = match.first.status;
                    }
                    final senderLabel =
                        (isGroup && !isMine && message.senderId != null)
                            ? senderNames[message.senderId]
                            : null;
                    return MessageBubble(
                      message: message,
                      isMine: isMine,
                      status: status,
                      senderLabel: senderLabel,
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

  String _titleText(
      bool isGroup, Conversation? conversation, Profile? displayProfile) {
    if (isGroup) return conversation?.name ?? 'Group';
    return displayProfile != null ? '@${displayProfile.username}' : 'Chat';
  }

  String _titleInitial(
      bool isGroup, Conversation? conversation, Profile? displayProfile) {
    if (isGroup) {
      final name = conversation?.name;
      return (name != null && name.isNotEmpty)
          ? name.substring(0, 1).toUpperCase()
          : 'G';
    }
    final name = displayProfile?.displayName?.isNotEmpty == true
        ? displayProfile!.displayName!
        : displayProfile?.username;
    return (name != null && name.isNotEmpty)
        ? name.substring(0, 1).toUpperCase()
        : '?';
  }
}
