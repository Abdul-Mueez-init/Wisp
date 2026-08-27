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
  void dispose() {
    ref.read(typingControllerProvider.notifier).stopTyping(widget.conversationId);
    final liveState = ref.read(liveLocationControllerProvider);
    if (liveState.isActive && liveState.conversationId == widget.conversationId) {
      ref.read(liveLocationControllerProvider.notifier).stop();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final myId = ref.watch(currentSessionProvider)?.user.id;
    final messagesAsync =
        ref.watch(messagesStreamProvider(widget.conversationId));
    final statusesAsync = ref.watch(messageStatusesStreamProvider);
    final sending = ref.watch(sendMessageControllerProvider).isLoading;
    final liveLocationState = ref.watch(liveLocationControllerProvider);
    final sharingLiveHere = liveLocationState.isActive &&
        liveLocationState.conversationId == widget.conversationId;
    final uploadingMedia =
        ref.watch(sendMediaMessageControllerProvider).isLoading ||
            ref.watch(sendLocationControllerProvider).isLoading;
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

    // Phase 4 — presence (direct chats only; groups have no single
    // "other user" to show a dot for) and typing, for both chat types.
    final livePresence = (!isGroup && displayProfile != null)
        ? ref.watch(watchProfileProvider(displayProfile.id))
        : null;
    final isOnline = livePresence?.value?.isOnline ?? displayProfile?.isOnline;
    final lastSeenAt =
        livePresence?.value?.lastSeenAt ?? displayProfile?.lastSeenAt;

    final typingUserIds =
        ref.watch(typingUsersStreamProvider(widget.conversationId)).value ??
            const [];
    final subtitleText = _subtitleText(
      isGroup: isGroup,
      typingUserIds: typingUserIds,
      senderNames: senderNames,
      isOnline: isOnline,
      lastSeenAt: lastSeenAt,
    );

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
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: AppColors.surfaceContainerHigh,
                    child: Text(
                      _titleInitial(
                          isGroup, resolvedConversation, displayProfile),
                      style: const TextStyle(color: AppColors.primary),
                    ),
                  ),
                  // design.md "Status & Indicators — Online Dot": 8px
                  // solid circle in Moderate Green.
                  if (!isGroup && isOnline == true)
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
                      _titleText(isGroup, resolvedConversation, displayProfile),
                      style: Theme.of(context).textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitleText != null)
                      Text(
                        subtitleText,
                        style:
                            Theme.of(context).textTheme.labelMedium?.copyWith(
                                  color: typingUserIds.isNotEmpty
                                      ? AppColors.primary
                                      : AppColors.onSurfaceVariant,
                                ),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                    if (sharingLiveHere)
            Container(
              width: double.infinity,
              color: AppColors.primaryContainer,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.pageMargin, vertical: 8),
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
                    child: const Text('Stop', style: TextStyle(color: AppColors.cream)),
                  ),
                ],
              ),
            ),
          ChatInputBar(
            ...
            onSendCurrentLocation: () => _sendMedia(
              () => ref
                  .read(sendLocationControllerProvider.notifier)
                  .sendCurrentLocation(conversationId: widget.conversationId),
              readError: () => ref.read(sendLocationControllerProvider).error,
            ),
            onStartLiveLocation: (duration) => _startLiveLocation(duration),
          ),
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
            uploadingMedia: uploadingMedia,
            onSend: (text) =>
                ref.read(sendMessageControllerProvider.notifier).sendText(
                      conversationId: widget.conversationId,
                      content: text,
                    ),
            onTextChanged: (text) => ref
                .read(typingControllerProvider.notifier)
                .onTextChanged(widget.conversationId, text),
            onSendImage: (bytes, ext) => _sendMedia(
              () => ref
                  .read(sendMediaMessageControllerProvider.notifier)
                  .sendImage(
                    conversationId: widget.conversationId,
                    bytes: bytes,
                    fileExt: ext,
                  ),
            ),
            onSendVideo: (bytes, ext) => _sendMedia(
              () => ref
                  .read(sendMediaMessageControllerProvider.notifier)
                  .sendVideo(
                    conversationId: widget.conversationId,
                    bytes: bytes,
                    fileExt: ext,
                  ),
            ),
            onSendDocument: (bytes, fileName) => _sendMedia(
              () => ref
                  .read(sendMediaMessageControllerProvider.notifier)
                  .sendDocument(
                    conversationId: widget.conversationId,
                    bytes: bytes,
                    fileName: fileName,
                  ),
            ),
            onSendVoice: (bytes) => _sendMedia(
              () => ref
                  .read(sendMediaMessageControllerProvider.notifier)
                  .sendVoice(
                    conversationId: widget.conversationId,
                    bytes: bytes,
                  ),
            ),
            onShareContact: (profile) => _sendMedia(
              () =>
                  ref.read(sendMessageControllerProvider.notifier).sendContact(
                        conversationId: widget.conversationId,
                        sharedContactId: profile.id,
                      ),
            ),
            onSendCurrentLocation: () => _sendMedia(
              () => ref
                  .read(sendLocationControllerProvider.notifier)
                  .sendCurrentLocation(conversationId: widget.conversationId),
              readError: () => ref.read(sendLocationControllerProvider).error,
            ),
          ),
        ],
      ),
    );
  }

  /// Shared error-surfacing wrapper for every Phase 5 media send —
  /// avoids repeating "await, check ok, read error, show snackbar"
  /// three times over (image/video/document).
  Future<void> _sendMedia(
    Future<bool> Function() send, {
    Object? Function()? readError,
  }) async {
    final ok = await send();
    if (!ok && mounted) {
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

  /// Phase 4 subtitle line shown under the title: typing takes priority
  /// over presence, since it's more immediately relevant.
  String? _subtitleText({
    required bool isGroup,
    required List<String> typingUserIds,
    required Map<String, String> senderNames,
    required bool? isOnline,
    required DateTime? lastSeenAt,
  }) {
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
    if (isGroup) return null; // no per-group presence concept (ERD.md)
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
