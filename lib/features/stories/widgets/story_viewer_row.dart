// lib/features/stories/widgets/story_viewer_row.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format_utils.dart';
import '../../../models/story.dart';
import '../../profile/providers/profile_provider.dart';

/// One row in the "Viewed by" bottom sheet (Part C, story viewer list) —
/// avatar, display name/username, and a relative "viewed at" timestamp.
/// One widget per file per architecture.md's coding conventions; not a
/// drop-in reuse of `story_ring_avatar.dart` (that's the small
/// ring-decorated avatar for the Status list row, not a taller list row
/// with a name + timestamp).
class StoryViewerRow extends ConsumerWidget {
  const StoryViewerRow({super.key, required this.viewer});

  final StoryViewer viewer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = viewer.profile;
    final avatarPath = profile.avatarUrl;
    final avatarUrl = avatarPath != null
        ? ref.read(profileRepositoryProvider).resolveAvatarUrl(avatarPath)
        : null;
    final name = profile.displayName ?? profile.username;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.pageMargin,
        vertical: AppSpacing.stackCompact,
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.surfaceContainerHigh,
            backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
            child: avatarUrl == null
                ? Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: const TextStyle(color: AppColors.cream),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(
                color: AppColors.cream,
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            formatRelativeShort(viewer.viewedAt),
            style: const TextStyle(
              color: AppColors.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
