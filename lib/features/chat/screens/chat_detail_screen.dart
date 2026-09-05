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
import '../providers/presence_provider.dart';
import '../providers/typing_provider.dart';
import '../widgets/chat_input_bar.dart';
import '../widgets/message_bubble.dart';
import '../../location/providers/location_provider.dart';
import '../../location/providers/live_location_provider.dart';
import '../../ai_agent/providers/ai_agent_provider.dart';
import '../../calls/providers/call_controller.dart';
import '../../../widgets/error_state_view.dart';

/// Phase 2 1-on-1 chat core, extended in Phase 3 to also render group
/// conversations (plan.md: "Group chat detail screen (reuses chat core
/// from Phase 2)") — same message stream/input, plus a group-aware app
/// bar and sender-name labels on received bubbles.
///
/// Performance architecture: isolated sub-widgets (_ChatDetailAppBar,
/// _ChatMessageList, _ChatLiveLocationBanner, _ChatInputArea) prevent
/// typing/presence/send-state ticks from causing full screen and bubble rebuilds.
class ChatDetailScreen extends ConsumerStatefulWidget {
  const ChatDetailScreen({
    super.key,
    required this.conversationId,
    this.otherProfile,
    this.groupConversation,
    this.isAiConversation = false,
  });

  final String conversationId;

  /// Passed via navigation `extra` when opening a direct chat from
  /// search results — avoids an extra fetch (Phase 2).
  final Profile? otherProfile;

  /// Passed via navigation `extra` right after creating a group — same
  /// reasoning as [otherProfile] (Phase 3).
  final Conversation? groupConversation;

  /// Phase 8 — true when this is the reserved single-member AI-DM
  /// conversation (`?ai=true` on the route, set by the "Wisp AI" chat
  /// list tile). There is no second real member/profile to fetch in
  /// this case, so this flag lets the screen skip the otherProfile/
  /// presence lookups entirely instead of them just resolving to null.
  final bool isAiConversation;

  @override
  ConsumerState<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends ConsumerState<ChatDetailScreen> {
  // Perf fix (WISP_PERFORMANCE_HANDOFF.md §6) — tracks the newest
  // message id we've already run a read-receipt sync for, so a
  // `messages` stream emission that doesn't actually add a new
  // incoming message doesn't re-run read-receipt writes.
  String? _lastSyncedMessageId;

  TypingController? _typingController;
  LiveLocationController? _liveLocationController;
  LiveLocationSharingState? _lastLiveLocationState;

  @override
  void initState() {
    super.initState();
    _typingController = ref.read(typingControllerProvider.notifier);
    _liveLocationController = ref.read(liveLocationControllerProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncReadReceipts());
  }

  /// Only re-runs the sync if the newest message in the conversation
  /// is one we haven't already synced.
  void _maybeSyncReadReceipts(List<Message> messages) {
    if (messages.isEmpty) return;
    final newestId = messages.last.id;
    if (newestId == _lastSyncedMessageId) return;
    _lastSyncedMessageId = newestId;
    _syncReadReceipts(messages);
  }

  /// Bounded read-receipt update: passes the visible/loaded incoming message IDs
  /// directly to `markRead()`, updating non-read status rows and inserting
  /// missing ones without full-history scans or redundant markDelivered calls.
  Future<void> _syncReadReceipts([List<Message>? messages]) async {
    final myId = ref.read(currentSessionProvider)?.user.id;
    if (myId == null) return;
    final repo = ref.read(messageRepositoryProvider);
    final incomingIds = messages
        ?.where((m) => m.senderId != myId)
        .map((m) => m.id)
        .toList();
    await repo.markRead(
      conversationId: widget.conversationId,
      myId: myId,
      messageIds: incomingIds,
    );
  }

  @override
  void deactivate() {
    final liveState = _lastLiveLocationState;
    if (liveState != null &&
        liveState.isActive &&
        liveState.conversationId == widget.conversationId) {
      _liveLocationController?.stop();
    }
    super.deactivate();
  }

  @override
  void dispose() {
    _typingController?.stopTyping(widget.conversationId);
    super.dispose();
  }

  void _onLiveLocationStateChanged(LiveLocationSharingState state) {
    _lastLiveLocationState = state;
  }

  Future<void> _startCall(Profile otherProfile, {required bool isVideo}) async {
    if (!ref.read(callControllerProvider).isIdle) return;
    context.push('/call');
    final controller = ref.read(callControllerProvider.notifier);
    final ok = await controller.startCall(
      conversationId: widget.conversationId,
      calleeId: otherProfile.id,
      isVideo: isVideo,
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not start the call.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _startLiveLocation(LiveLocationDuration duration) async {
    final ok = await ref
        .read(liveLocationControllerProvider.notifier)
        .start(conversationId: widget.conversationId, duration: duration);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not start live location.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final myId = ref.watch(currentSessionProvider)?.user.id;

    // Listen to message window events to sync read receipts
    ref.listen(chatMessagesControllerProvider(widget.conversationId),
        (prev, next) {
      _maybeSyncReadReceipts(next.messages);
    });

    return Scaffold(
      backgroundColor: AppColors.backgroundBase,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: _ChatDetailAppBar(
          conversationId: widget.conversationId,
          otherProfile: widget.otherProfile,
          groupConversation: widget.groupConversation,
          isAiConversation: widget.isAiConversation,
          onStartCall: _startCall,
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _ChatMessageList(
              conversationId: widget.conversationId,
              isAiConversation: widget.isAiConversation,
              myId: myId,
            ),
          ),
          _ChatLiveLocationBanner(
            conversationId: widget.conversationId,
            onStateChanged: _onLiveLocationStateChanged,
          ),
          _ChatInputArea(
            conversationId: widget.conversationId,
            isAiConversation: widget.isAiConversation,
            onStartLiveLocation: _startLiveLocation,
          ),
        ],
      ),
    );
  }
}

/// Isolated App Bar: watches typing, presence, group members, and thinking state.
/// Typing/presence updates rebuild ONLY this bar, leaving message bubbles untouched.
class _ChatDetailAppBar extends ConsumerWidget {
  const _ChatDetailAppBar({
    required this.conversationId,
    required this.otherProfile,
    required this.groupConversation,
    required this.isAiConversation,
    required this.onStartCall,
  });

  final String conversationId;
  final Profile? otherProfile;
  final Conversation? groupConversation;
  final bool isAiConversation;
  final Future<void> Function(Profile otherProfile, {required bool isVideo})
      onStartCall;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final needsConversationFetch =
        otherProfile == null && groupConversation == null;
    final conversationAsync = needsConversationFetch
        ? ref.watch(conversationByIdProvider(conversationId))
        : null;
    final resolvedConversation =
        groupConversation ?? conversationAsync?.value;
    final isGroup = resolvedConversation?.isGroup ?? false;

    final otherProfileAsync =
        (!isGroup && !isAiConversation && otherProfile == null)
            ? ref.watch(otherDirectMemberProvider(conversationId))
            : null;
    final displayProfile = otherProfile ?? otherProfileAsync?.value;

    final membersAsync =
        isGroup ? ref.watch(groupMembersProvider(conversationId)) : null;
    final senderNames = <String, String>{
      for (final m in membersAsync?.value ?? const [])
        m.profile.id: m.profile.displayName?.isNotEmpty == true
            ? m.profile.displayName!
            : '@${m.profile.username}',
    };

    final centralPresence = (!isGroup && displayProfile != null)
        ? ref.watch(presenceByIdProvider.select((m) => m[displayProfile.id]))
        : null;
    final isOnline = centralPresence?.isOnline ?? displayProfile?.isOnline;
    final lastSeenAt =
        centralPresence?.lastSeenAt ?? displayProfile?.lastSeenAt;

    final typingUserIds =
        ref.watch(typingUsersStreamProvider(conversationId)).value ??
            const [];

    final aiThinking =
        ref.watch(aiAgentThinkingProvider(conversationId));
    final subtitleText = isAiConversation && aiThinking
        ? 'Wisp is typing…'
        : _subtitleText(
            isGroup: isGroup,
            typingUserIds: typingUserIds,
            senderNames: senderNames,
            isOnline: isOnline,
            lastSeenAt: lastSeenAt,
            aiThinking: aiThinking,
          );

    return AppBar(
      titleSpacing: 0,
      title: InkWell(
        onTap: isGroup
            ? () => context.push('/group/$conversationId/members')
            : null,
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: isAiConversation
                      ? AppColors.primaryContainer
                      : AppColors.surfaceContainerHigh,
                  child: isAiConversation
                      ? const Icon(Icons.auto_awesome,
                          size: 18, color: AppColors.primary)
                      : Text(
                          _titleInitial(
                              isGroup, resolvedConversation, displayProfile),
                          style: const TextStyle(color: AppColors.primary),
                        ),
                ),
                if (!isGroup && !isAiConversation && isOnline == true)
                  Positioned(
                    right: -1,
                    bottom: -1,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.backgroundBase,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    isAiConversation
                        ? 'Wisp AI'
                        : _titleText(
                            isGroup, resolvedConversation, displayProfile),
                    style: Theme.of(context).textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitleText != null)
                    Text(
                      subtitleText,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: typingUserIds.isNotEmpty || aiThinking
                                ? AppColors.primary
                                : AppColors.onSurfaceVariant,
                          ),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (isGroup)
              const Icon(Icons.chevron_right, color: AppColors.outline),
          ],
        ),
      ),
      actions: (!isGroup && !isAiConversation && displayProfile != null)
          ? [
              IconButton(
                tooltip: 'Video call',
                icon: const Icon(Icons.videocam_outlined),
                onPressed: () => onStartCall(displayProfile, isVideo: true),
              ),
              IconButton(
                tooltip: 'Voice call',
                icon: const Icon(Icons.call_outlined),
                onPressed: () => onStartCall(displayProfile, isVideo: false),
              ),
            ]
          : null,
    );
  }

  String? _subtitleText({
    required bool isGroup,
    required List<String> typingUserIds,
    required Map<String, String> senderNames,
    required bool? isOnline,
    required DateTime? lastSeenAt,
    bool aiThinking = false,
  }) {
    if (aiThinking) return 'Wisp is typing…';
    if (typingUserIds.isNotEmpty) {
      if (!isGroup) return 'typing…';
      final names = typingUserIds
          .map((id) => senderNames[id] ?? 'Someone')
          .take(2)
          .join(', ');
      return typingUserIds.length > 2
          ? '$names and others typing…'
          : '$names typing…';
    }
    if (isGroup) return null;
    if (isOnline == true) return 'online';
    if (lastSeenAt != null) return _lastSeenLabel(lastSeenAt);
    return null;
  }

  String _lastSeenLabel(DateTime lastSeenAt) {
    final diff = DateTime.now().difference(lastSeenAt);
    if (diff.inMinutes < 1) return 'last seen just now';
    if (diff.inMinutes < 60) return 'last seen ${diff.inMinutes}m ago';
    if (diff.inHours < 24) return 'last seen ${diff.inHours}h ago';
    return 'last seen ${diff.inDays}d ago';
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

/// Isolated Message List: watches only chatMessagesControllerProvider.
/// List indexing is computed as `messages.length - 1 - index` directly,
/// avoiding `.reversed.toList()` allocations on every frame.
class _ChatMessageList extends ConsumerWidget {
  const _ChatMessageList({
    required this.conversationId,
    required this.isAiConversation,
    required this.myId,
  });

  final String conversationId;
  final bool isAiConversation;
  final String? myId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatState = ref.watch(chatMessagesControllerProvider(conversationId));

    if (chatState.isLoadingInitial) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    if (chatState.messages.isEmpty && chatState.error != null) {
      return ErrorStateView(
        error: chatState.error!,
        onRetry: () => ref.invalidate(
          chatMessagesControllerProvider(conversationId),
        ),
      );
    }

    if (chatState.messages.isEmpty) {
      if (isAiConversation) {
        return _AiWelcomeView(
          onSuggestionTap: (text) => ref
              .read(sendMessageControllerProvider.notifier)
              .sendText(
                conversationId: conversationId,
                content: text,
                isAiConversation: true,
              ),
        );
      }
      return Center(
        child: Text(
          'Say hi 👋',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    final messages = chatState.messages;
    final messagesCount = messages.length;

    // Member names for group chats
    final groupMembers = ref.watch(
      groupMembersProvider(conversationId).select((m) => m.value),
    );
    final senderNames = <String, String>{
      for (final m in groupMembers ?? const [])
        m.profile.id: m.profile.displayName?.isNotEmpty == true
            ? m.profile.displayName!
            : '@${m.profile.username}',
    };

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        final metrics = notification.metrics;
        if (metrics.maxScrollExtent > 0 &&
            metrics.pixels >= metrics.maxScrollExtent - 600) {
          ref
              .read(chatMessagesControllerProvider(conversationId).notifier)
              .loadOlder();
        }
        return false;
      },
      child: ListView.builder(
        reverse: true,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.pageMargin,
          vertical: 12,
        ),
        itemCount: messagesCount + (chatState.isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == messagesCount) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          // Zero-allocation reversed index into oldest-first collection
          final Message message = messages[messagesCount - 1 - index];
          final isMine = message.senderId == myId;
          final senderLabel = (!isMine && message.senderId != null)
              ? senderNames[message.senderId]
              : null;

          return MessageBubble(
            key: ValueKey(message.id),
            message: message,
            isMine: isMine,
            senderLabel: senderLabel,
          );
        },
      ),
    );
  }
}

/// Isolated Live Location Banner: rebuilds only when live location state changes.
class _ChatLiveLocationBanner extends ConsumerWidget {
  const _ChatLiveLocationBanner({
    required this.conversationId,
    required this.onStateChanged,
  });

  final String conversationId;
  final ValueChanged<LiveLocationSharingState> onStateChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liveLocationState = ref.watch(liveLocationControllerProvider);
    onStateChanged(liveLocationState);

    final sharingLiveHere = liveLocationState.isActive &&
        liveLocationState.conversationId == conversationId;

    if (!sharingLiveHere) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      color: AppColors.primaryContainer,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.pageMargin,
        vertical: 8,
      ),
      child: Row(
        children: [
          const Icon(Icons.location_on, size: 16, color: AppColors.cream),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Sharing live location',
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: AppColors.cream),
            ),
          ),
          TextButton(
            onPressed: () =>
                ref.read(liveLocationControllerProvider.notifier).stop(),
            child: const Text('Stop',
                style: TextStyle(color: AppColors.cream)),
          ),
        ],
      ),
    );
  }
}

/// Isolated Input Area: rebuilds only when sending or uploading state changes.
class _ChatInputArea extends ConsumerWidget {
  const _ChatInputArea({
    required this.conversationId,
    required this.isAiConversation,
    required this.onStartLiveLocation,
  });

  final String conversationId;
  final bool isAiConversation;
  final Future<void> Function(LiveLocationDuration) onStartLiveLocation;

  Future<void> _sendMedia(
    BuildContext context,
    WidgetRef ref,
    Future<bool> Function() send, {
    Object? Function()? readError,
  }) async {
    final ok = await send();
    if (!ok && context.mounted) {
      final error = readError != null
          ? readError()
          : ref.read(sendMediaMessageControllerProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error?.toString() ?? 'Could not send attachment.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sending = ref.watch(
      sendMessageControllerProvider.select((s) => s.isLoading),
    );
    final uploadingMedia = ref.watch(
          sendMediaMessageControllerProvider.select((s) => s.isLoading),
        ) ||
        ref.watch(
          sendLocationControllerProvider.select((s) => s.isLoading),
        );

    return ChatInputBar(
      sending: sending,
      uploadingMedia: uploadingMedia,
      onSend: (text) =>
          ref.read(sendMessageControllerProvider.notifier).sendText(
                conversationId: conversationId,
                content: text,
                isAiConversation: isAiConversation,
              ),
      onTextChanged: (text) => ref
          .read(typingControllerProvider.notifier)
          .onTextChanged(conversationId, text),
      onSendImage: (bytes, ext) => _sendMedia(
        context,
        ref,
        () => ref
            .read(sendMediaMessageControllerProvider.notifier)
            .sendImage(
              conversationId: conversationId,
              bytes: bytes,
              fileExt: ext,
            ),
      ),
      onSendVideo: (bytes, ext) => _sendMedia(
        context,
        ref,
        () => ref
            .read(sendMediaMessageControllerProvider.notifier)
            .sendVideo(
              conversationId: conversationId,
              bytes: bytes,
              fileExt: ext,
            ),
      ),
      onSendDocument: (bytes, fileName) => _sendMedia(
        context,
        ref,
        () => ref
            .read(sendMediaMessageControllerProvider.notifier)
            .sendDocument(
              conversationId: conversationId,
              bytes: bytes,
              fileName: fileName,
            ),
      ),
      onSendVoice: (bytes) => _sendMedia(
        context,
        ref,
        () => ref
            .read(sendMediaMessageControllerProvider.notifier)
            .sendVoice(
              conversationId: conversationId,
              bytes: bytes,
            ),
      ),
      onShareContact: (profile) => _sendMedia(
        context,
        ref,
        () => ref
            .read(sendMessageControllerProvider.notifier)
            .sendContact(
              conversationId: conversationId,
              sharedContactId: profile.id,
            ),
      ),
      onSendCurrentLocation: () => _sendMedia(
        context,
        ref,
        () => ref
            .read(sendLocationControllerProvider.notifier)
            .sendCurrentLocation(conversationId: conversationId),
        readError: () => ref.read(sendLocationControllerProvider).error,
      ),
      onStartLiveLocation: onStartLiveLocation,
    );
  }
}

/// Phase 8 — shown only when the AI conversation has zero messages yet
class _AiWelcomeView extends StatelessWidget {
  const _AiWelcomeView({required this.onSuggestionTap});

  final ValueChanged<String> onSuggestionTap;

  static const _suggestions = <(IconData, String)>[
    (Icons.summarize_outlined, 'Summarize my recent chats'),
    (Icons.edit_note_outlined, 'Help me draft a reply'),
    (Icons.chat_bubble_outline, 'Give me a good icebreaker'),
    (Icons.lightbulb_outline, 'Explain something to me'),
    (Icons.celebration_outlined, 'Tell me something fun'),
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.pageMargin,
        vertical: 24,
      ),
      children: [
        const SizedBox(height: 24),
        const CircleAvatar(
          radius: 32,
          backgroundColor: AppColors.primaryContainer,
          child: Icon(Icons.auto_awesome, size: 32, color: AppColors.primary),
        ),
        const SizedBox(height: 16),
        Text(
          'Hi, I\'m Wisp AI',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 4),
        Text(
          'Ask me anything, or try one of these',
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: AppColors.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        for (final (icon, label) in _suggestions)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.stackDefault),
            child: _SuggestionChip(
              icon: icon,
              label: label,
              onTap: () => onSuggestionTap(label),
            ),
          ),
      ],
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(AppRadius.buttonInput),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.buttonInput),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.paddingBubbleX,
            vertical: AppSpacing.paddingBubbleY,
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: AppColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
