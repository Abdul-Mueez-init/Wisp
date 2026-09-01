// lib/features/chat/widgets/message_bubble.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format_utils.dart';
import '../../../models/message.dart';
import '../../../models/profile.dart';
import '../../profile/providers/profile_provider.dart';
import '../../voice_notes/widgets/voice_note_bubble.dart';
import '../providers/conversation_provider.dart';
import '../providers/message_provider.dart';
import 'video_player_view.dart';
import '../../location/widgets/location_bubble_content.dart';

/// Renders per design.md "Message Bubbles": Sent = primary-container bg,
/// Cream text, right-aligned, 14px radius with a 4px "tail" corner;
/// Received = Surface-Raised bg, left-aligned, same shape.
///
/// Batch 5a/5b/5c/5d: 'text', 'image', 'video', 'document', 'voice',
/// 'contact' render fully. The two 'location_*' types render as a
/// neutral placeholder until Batch 5e ships — the agreed build
/// sequence, not a shortcut.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    this.senderLabel,
  });

  final Message message;
  final bool isMine;
  final String? senderLabel;

  static const _clippedTypes = {
    'image',
    'video',
    "location_current",
    "location_live"
  };

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(AppRadius.messageBubble),
      topRight: const Radius.circular(AppRadius.messageBubble),
      bottomLeft: Radius.circular(
        isMine ? AppRadius.messageBubble : AppRadius.messageBubbleTail,
      ),
      bottomRight: Radius.circular(
        isMine ? AppRadius.messageBubbleTail : AppRadius.messageBubble,
      ),
    );
    final bubbleColor =
        isMine ? AppColors.primaryContainer : AppColors.surfaceRaised;

    final Widget bubble = _clippedTypes.contains(message.type)
        ? ClipRRect(
            borderRadius: radius,
            child: Container(
              decoration: BoxDecoration(color: bubbleColor),
              child: switch (message.type) {
                'image' =>
                  _ImageBubbleContent(message: message, isMine: isMine),
                'video' =>
                  _VideoBubbleContent(message: message, isMine: isMine),
                _ => LocationBubbleContent(message: message, isMine: isMine),
              },
            ),
          )
        : Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.paddingBubbleX,
              vertical: AppSpacing.paddingBubbleY,
            ),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: radius,
              border: message.isAiMessage
                  ? Border.all(color: AppColors.primary, width: 1)
                  : null,
            ),
            child: _standardContent(context),
          );

    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.bubbleSameSender / 2,
      ),
      child: Column(
        crossAxisAlignment:
            isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (senderLabel != null && !isMine)
            Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 2),
              child: Text(
                senderLabel!,
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: AppColors.primary),
              ),
            ),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            child: bubble,
          ),
          Padding(
            padding: EdgeInsets.only(
              top: 2,
              right: isMine ? 4 : 0,
              left: isMine ? 0 : 12,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatTime(message.createdAt),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                if (isMine) ...[
                  const SizedBox(width: 4),
                  _StatusTick(messageId: message.id),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 'text', 'document', 'voice', 'contact', plus the not-yet-
  /// implemented location placeholder. Image/video are handled
  /// separately above since they need the clipped, edge-to-edge bubble
  /// treatment.
  Widget _standardContent(BuildContext context) {
    if (message.type == 'text') {
      // Phase 7: translation only ever renders on the receiver's side
      // (PRD.md §10 — translation targets the receiver's preferred
      // language, so the sender's own outgoing bubble always shows
      // exactly what they typed, nothing more).
      final showTranslation = !isMine && message.translatedContent != null;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (message.isAiMessage)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'AI',
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: AppColors.primary),
              ),
            ),
          if (showTranslation) ...[
            Text(
              message.content ?? '',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
            ),
            const SizedBox(height: 3),
          ],
          Text(
            showTranslation
                ? message.translatedContent!
                : (message.content ?? ''),
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: isMine ? AppColors.cream : AppColors.onSurface,
                ),
          ),
        ],
      );
    }

    if (message.type == 'document') {
      return _DocumentBubbleContent(message: message, isMine: isMine);
    }

    if (message.type == 'voice') {
      return VoiceNoteBubble(message: message, isMine: isMine);
    }

    if (message.type == 'contact') {
      return _ContactBubbleContent(message: message, isMine: isMine);
    }

    final placeholder = _placeholderFor(message.type);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(placeholder.$1,
            size: 18, color: isMine ? AppColors.cream : AppColors.onSurface),
        const SizedBox(width: 8),
        Text(
          placeholder.$2,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: isMine ? AppColors.cream : AppColors.onSurface,
                fontStyle: FontStyle.italic,
              ),
        ),
      ],
    );
  }

  (IconData, String) _placeholderFor(String type) {
    return (Icons.help_outline, 'Unsupported message');
  }

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }
}

/// Resolves the message's storage path to a signed URL and renders it,
/// with an optional caption padded below (still inside the same
/// clipped bubble). Tapping opens a full-screen viewer.
class _ImageBubbleContent extends ConsumerWidget {
  const _ImageBubbleContent({required this.message, required this.isMine});

  final Message message;
  final bool isMine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = message.mediaUrl;
    final caption = message.content?.trim();

    if (path == null) {
      return const SizedBox(
        height: 160,
        child: Center(child: Icon(Icons.broken_image_outlined)),
      );
    }

    final urlAsync = ref.watch(mediaSignedUrlProvider(path));

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        urlAsync.when(
          data: (url) => GestureDetector(
            onTap: () => _openFullScreen(context, url),
            child: SizedBox(
              height: 220,
              width: double.infinity,
              child: Image.network(
                url,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  );
                },
                errorBuilder: (context, error, stack) => const Center(
                  child: Icon(Icons.broken_image_outlined),
                ),
              ),
            ),
          ),
          loading: () => const SizedBox(
            height: 220,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (e, _) => const SizedBox(
            height: 160,
            child: Center(child: Icon(Icons.broken_image_outlined)),
          ),
        ),
        if (caption != null && caption.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.paddingBubbleX,
              8,
              AppSpacing.paddingBubbleX,
              AppSpacing.paddingBubbleY,
            ),
            child: Text(
              caption,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: isMine ? AppColors.cream : AppColors.onSurface,
                  ),
            ),
          ),
      ],
    );
  }

  void _openFullScreen(BuildContext context, String url) {
    showDialog(
      context: context,
      barrierColor: Colors.black,
      builder: (context) => GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: AppColors.cream),
          ),
          body: Center(child: InteractiveViewer(child: Image.network(url))),
        ),
      ),
    );
  }
}

/// Batch 5b — video bubble. No thumbnail-generation package is used
/// (would add a native dependency for one cosmetic detail); instead a
/// flat cover with a play button, same as WhatsApp shows before a
/// thumbnail loads. Tapping opens [VideoPlayerView] full-screen.
class _VideoBubbleContent extends ConsumerWidget {
  const _VideoBubbleContent({required this.message, required this.isMine});

  final Message message;
  final bool isMine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = message.mediaUrl;
    final caption = message.content?.trim();

    if (path == null) {
      return const SizedBox(
        height: 160,
        child: Center(child: Icon(Icons.videocam_off_outlined)),
      );
    }

    final urlAsync = ref.watch(mediaSignedUrlProvider(path));

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        urlAsync.when(
          data: (url) => GestureDetector(
            onTap: () => VideoPlayerView.open(context, url),
            child: Container(
              height: 220,
              width: double.infinity,
              color: Colors.black26,
              child: const Center(
                child: CircleAvatar(
                  radius: 28,
                  backgroundColor: Colors.black45,
                  child: Icon(Icons.play_arrow_rounded,
                      color: AppColors.cream, size: 32),
                ),
              ),
            ),
          ),
          loading: () => const SizedBox(
            height: 220,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (e, _) => const SizedBox(
            height: 160,
            child: Center(child: Icon(Icons.videocam_off_outlined)),
          ),
        ),
        if (caption != null && caption.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.paddingBubbleX,
              8,
              AppSpacing.paddingBubbleX,
              AppSpacing.paddingBubbleY,
            ),
            child: Text(
              caption,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: isMine ? AppColors.cream : AppColors.onSurface,
                  ),
            ),
          ),
      ],
    );
  }
}

/// Perf fix (WISP_PERFORMANCE_HANDOFF.md §4/§5) — the only part of a
/// sent bubble that changes after the message lands is its delivery/
/// read tick. Isolating it here with `.select` means a status update
/// rebuilds just this small icon, not the bubble, the message list, or
/// the screen. Same 'sent'/'delivered'/'read' → icon/color mapping as
/// before, just resolved locally instead of via a passed-in parameter.
class _StatusTick extends ConsumerWidget {
  const _StatusTick({required this.messageId});

  final String messageId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(
      messageStatusByIdProvider.select((map) => map[messageId]?.status),
    );
    return Icon(
      _statusIcon(status),
      size: 14,
      color: status == 'read' ? AppColors.primary : AppColors.outline,
    );
  }

  IconData _statusIcon(String? status) {
    switch (status) {
      case 'read':
      case 'delivered':
        return Icons.done_all_rounded;
      default:
        return Icons.done_rounded;
    }
  }
}

/// Batch 5b — document bubble: icon, real filename, formatted size,
/// tap opens the signed URL via the OS/browser (which handles the
/// actual download) rather than this app managing file-system writes
/// and native "open with" plumbing itself.
class _DocumentBubbleContent extends ConsumerWidget {
  const _DocumentBubbleContent({required this.message, required this.isMine});

  final Message message;
  final bool isMine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = message.mediaUrl;
    final textColor = isMine ? AppColors.cream : AppColors.onSurface;

    if (path == null) {
      return Text(
        'Document unavailable',
        style:
            Theme.of(context).textTheme.bodyMedium?.copyWith(color: textColor),
      );
    }

    final infoAsync = ref.watch(mediaFileInfoProvider(path));

    return infoAsync.when(
      data: (info) => InkWell(
        onTap: () => _openDocument(context, info.url),
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: const Icon(Icons.insert_drive_file_outlined,
                  color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    info.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(color: textColor),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatFileSize(info.sizeBytes),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: isMine
                              ? AppColors.cream.withValues(alpha: 0.7)
                              : AppColors.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.download_outlined, color: textColor),
          ],
        ),
      ),
      loading: () => const SizedBox(
        height: 40,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (e, _) => Text(
        'Could not load document',
        style:
            Theme.of(context).textTheme.bodyMedium?.copyWith(color: textColor),
      ),
    );
  }

  Future<void> _openDocument(BuildContext context, String url) async {
    final ok =
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open document.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }
}

/// Batch 5d — contact-share bubble: avatar, @username, display name,
/// tap opens/starts a direct chat with that user (same
/// `startConversationControllerProvider` flow as tapping a search
/// result in `UserSearchScreen`). Avatar resolves via the public
/// `avatars` bucket (synchronous `getPublicUrl`, unlike chat-media's
/// signed-URL flow) since that bucket is public per architecture.md.
class _ContactBubbleContent extends ConsumerWidget {
  const _ContactBubbleContent({required this.message, required this.isMine});

  final Message message;
  final bool isMine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contactId = message.sharedContactId;
    final textColor = isMine ? AppColors.cream : AppColors.onSurface;

    if (contactId == null) {
      return Text(
        'Contact unavailable',
        style:
            Theme.of(context).textTheme.bodyMedium?.copyWith(color: textColor),
      );
    }

    final profileAsync = ref.watch(profileByIdProvider(contactId));

    return profileAsync.when(
      data: (profile) {
        if (profile == null) {
          return Text(
            'Contact no longer available',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: textColor),
          );
        }
        final nameForInitial = profile.displayName?.isNotEmpty == true
            ? profile.displayName!
            : profile.username;
        final avatarUrl = profile.avatarUrl != null
            ? ref
                .read(profileRepositoryProvider)
                .resolveAvatarUrl(profile.avatarUrl!)
            : null;

        return InkWell(
          onTap: () => _openContact(context, ref, profile),
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.surfaceContainerHigh,
                backgroundImage:
                    avatarUrl != null ? NetworkImage(avatarUrl) : null,
                child: avatarUrl == null
                    ? Text(
                        nameForInitial.substring(0, 1).toUpperCase(),
                        style: const TextStyle(color: AppColors.primary),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '@${profile.username}',
                      style: Theme.of(context)
                          .textTheme
                          .bodyLarge
                          ?.copyWith(color: textColor),
                    ),
                    if (profile.displayName != null)
                      Text(
                        profile.displayName!,
                        style:
                            Theme.of(context).textTheme.labelMedium?.copyWith(
                                  color: isMine
                                      ? AppColors.cream.withValues(alpha: 0.7)
                                      : AppColors.onSurfaceVariant,
                                ),
                      ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: textColor),
            ],
          ),
        );
      },
      loading: () => const SizedBox(
        height: 40,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (e, _) => Text(
        'Could not load contact',
        style:
            Theme.of(context).textTheme.bodyMedium?.copyWith(color: textColor),
      ),
    );
  }

  Future<void> _openContact(
    BuildContext context,
    WidgetRef ref,
    Profile profile,
  ) async {
    final conversationId = await ref
        .read(startConversationControllerProvider.notifier)
        .startDirectConversationWith(profile.id);
    if (!context.mounted) return;
    if (conversationId != null) {
      context.push('/chat/$conversationId', extra: profile);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open chat.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }
}
