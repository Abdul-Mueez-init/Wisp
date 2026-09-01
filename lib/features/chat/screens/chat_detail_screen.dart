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
  // incoming message (e.g. a translation or voice-transcript UPDATE
  // on an existing row, or this user's own outgoing message) doesn't
  // re-run markDelivered/markRead's several queries for nothing.
  // Semantics are unchanged — every genuinely new message still gets
  // synced, exactly as before.
  String? _lastSyncedMessageId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncReadReceipts());
  }

  /// Only re-runs the sync if the newest message in the conversation
  /// is one we haven't already synced. [watchMessages] orders
  /// ascending by `created_at`, so `messages.last` is the newest.
  void _maybeSyncReadReceipts(List<Message> messages) {
    if (messages.isEmpty) return;
    final newestId = messages.last.id;
    if (newestId == _lastSyncedMessageId) return;
    _lastSyncedMessageId = newestId;
    _syncReadReceipts();
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
    ref
        .read(typingControllerProvider.notifier)
        .stopTyping(widget.conversationId);
    final liveState = ref.read(liveLocationControllerProvider);
    if (liveState.isActive &&
        liveState.conversationId == widget.conversationId) {
      ref.read(liveLocationControllerProvider.notifier).stop();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final myId = ref.watch(currentSessionProvider)?.user.id;
    final messagesAsync =
        ref.watch(messagesStreamProvider(widget.conversationId));
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

    final otherProfileAsync =
        (!isGroup && !widget.isAiConversation && widget.otherProfile == null)
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
      final messages = next.value;
      if (messages != null) _maybeSyncReadReceipts(messages);
    });

    // Phase 4 — presence (direct chats only; groups have no single
    // "other user" to show a dot for) and typing, for both chat types.
    // Perf fix (WISP_PERFORMANCE_HANDOFF.md §10) — reads from the
    // centralized `presenceByIdProvider` map (one app-wide realtime
    // source) instead of opening a dedicated per-user stream for this
    // screen. Same fallback behavior as before: until presence data
    // is available for this user, falls back to the static
    // `displayProfile` passed in via navigation.
    final centralPresence = (!isGroup && displayProfile != null)
        ? ref.watch(presenceByIdProvider.select((m) => m[displayProfile.id]))
        : null;
    final isOnline = centralPresence?.isOnline ?? displayProfile?.isOnline;
    final lastSeenAt =
        centralPresence?.lastSeenAt ?? displayProfile?.lastSeenAt;

    final typingUserIds =
        ref.watch(typingUsersStreamProvider(widget.conversationId)).value ??
            const [];

    final aiThinking =
        ref.watch(aiAgentThinkingProvider(widget.conversationId));
    final subtitleText = widget.isAiConversation && aiThinking
        ? 'Wisp is typing…'
        : _subtitleText(
            isGroup: isGroup,
            typingUserIds: typingUserIds,
            senderNames: senderNames,
            isOnline: isOnline,
            lastSeenAt: lastSeenAt,
            aiThinking: aiThinking,
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
                    backgroundColor: widget.isAiConversation
                        ? AppColors.primaryContainer
                        : AppColors.surfaceContainerHigh,
                    child: widget.isAiConversation
                        ? const Icon(Icons.auto_awesome,
                            size: 18, color: AppColors.primary)
                        : Text(
                            _titleInitial(
                                isGroup, resolvedConversation, displayProfile),
                            style: const TextStyle(color: AppColors.primary),
                          ),
                  ),
                  // design.md "Status & Indicators — Online Dot": 8px
                  // solid circle in Moderate Green.
                  if (!isGroup && !widget.isAiConversation && isOnline == true)
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
                      widget.isAiConversation
                          ? 'Wisp AI'
                          : _titleText(
                              isGroup, resolvedConversation, displayProfile),
                      style: Theme.of(context).textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitleText != null)
                      Text(
                        subtitleText,
                        style:
                            Theme.of(context).textTheme.labelMedium?.copyWith(
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
        // Phase 10, Batch 10c — call icons per design.md's Chat Detail
        // 1-on-1 Stitch export (video then phone, right-aligned).
        // 1-on-1 only per PRD.md §11: hidden for groups and the AI
        // conversation, and only shown once the other member's id is
        // known (needed for CallController.startCall's calleeId).
        actions: (!isGroup &&
                !widget.isAiConversation &&
                displayProfile != null)
            ? [
                IconButton(
                  tooltip: 'Video call',
                  icon: const Icon(Icons.videocam_outlined),
                  onPressed: () => _startCall(displayProfile, isVideo: true),
                ),
                IconButton(
                  tooltip: 'Voice call',
                  icon: const Icon(Icons.call_outlined),
                  onPressed: () => _startCall(displayProfile, isVideo: false),
                ),
              ]
            : null,
      ),
      body: Column(
        children: [
          Expanded(
            child: messagesAsync.when(
              data: (messages) {
                if (messages.isEmpty) {
                  if (widget.isAiConversation) {
                    return _AiWelcomeView(
                      onSuggestionTap: (text) => ref
                          .read(sendMessageControllerProvider.notifier)
                          .sendText(
                            conversationId: widget.conversationId,
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
                final reversed = messages.reversed.toList();

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
                    // Status is no longer looked up here — MessageBubble's
                    // leaf `_StatusTick` resolves it itself via the
                    // indexed `messageStatusByIdProvider`, so a status
                    // update no longer has to rebuild this whole list.
                    final senderLabel =
                        (isGroup && !isMine && message.senderId != null)
                            ? senderNames[message.senderId]
                            : null;
                    return MessageBubble(
                      key: ValueKey(message.id),
                      message: message,
                      isMine: isMine,
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
          if (sharingLiveHere)
            Container(
              width: double.infinity,
              color: AppColors.primaryContainer,
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.pageMargin, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.location_on,
                      size: 16, color: AppColors.cream),
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
                    onPressed: () => ref
                        .read(liveLocationControllerProvider.notifier)
                        .stop(),
                    child: const Text('Stop',
                        style: TextStyle(color: AppColors.cream)),
                  ),
                ],
              ),
            ),
          ChatInputBar(
            sending: sending,
            uploadingMedia: uploadingMedia,
            onSend: (text) =>
                ref.read(sendMessageControllerProvider.notifier).sendText(
                      conversationId: widget.conversationId,
                      content: text,
                      isAiConversation: widget.isAiConversation,
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
            onStartLiveLocation: _startLiveLocation,
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

  /// Places a call from this chat's call/video icons. `CallController`
  /// itself refuses to start a second call if one's already active on
  /// this device (returns false, state untouched) — that failure and a
  /// genuine start failure look the same here, both just don't push.
  Future<void> _startCall(Profile otherProfile, {required bool isVideo}) async {
    final controller = ref.read(callControllerProvider.notifier);
    final ok = await controller.startCall(
      conversationId: widget.conversationId,
      calleeId: otherProfile.id,
      isVideo: isVideo,
    );
    if (ok && mounted) {
      context.push('/call');
    } else if (!ok && mounted) {
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

  /// Phase 4 subtitle line shown under the title: typing takes priority
  /// over presence, since it's more immediately relevant.
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

/// Phase 8 — shown only when the AI conversation has zero messages yet
/// (the same screen switches to the ordinary bubble list the moment a
/// first message exists, per `messagesAsync`'s realtime stream — no
/// separate route). Mirrors WhatsApp's "Ask Meta AI" landing screen:
/// a greeting plus a handful of tappable suggestions that send
/// immediately as the first message, using the exact same
/// `SendMessageController.sendText(isAiConversation: true)` path a
/// typed message would use — this widget only supplies the text.
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
