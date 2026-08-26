import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/message.dart';

/// Renders per design.md "Message Bubbles": Sent = primary-container bg,
/// Cream text, right-aligned, 14px radius with a 4px "tail" corner;
/// Received = Surface-Raised bg, left-aligned, same shape. Only 'text'
/// messages are rendered — other `type` values land in Phase 5/9 (see
/// Message model doc comment).
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    this.status,
    this.senderLabel,
  });

  final Message message;
  final bool isMine;
  final String? status; // 'sent' | 'delivered' | 'read' — mine only
  /// Sender's name shown above received bubbles in group chats only —
  /// 1-on-1 chats already identify the other participant in the app bar.
  final String? senderLabel;

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
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.paddingBubbleX,
                vertical: AppSpacing.paddingBubbleY,
              ),
              decoration: BoxDecoration(
                color: isMine
                    ? AppColors.primaryContainer
                    : AppColors.surfaceRaised,
                borderRadius: radius,
                border: message.isAiMessage
                    ? Border.all(color: AppColors.primary, width: 1)
                    : null,
              ),
              child: Column(
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
                  Text(
                    message.content ?? '',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: isMine ? AppColors.cream : AppColors.onSurface,
                        ),
                  ),
                ],
              ),
            ),
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
                  Icon(
                    _statusIcon(status),
                    size: 14,
                    color: status == 'read'
                        ? AppColors.primary
                        : AppColors.outline,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
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

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }
}
