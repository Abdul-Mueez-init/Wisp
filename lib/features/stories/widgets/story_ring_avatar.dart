// lib/features/stories/widgets/story_ring_avatar.dart
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// design.md "Status & Indicators" — Story Ring: 2px ring around an
/// avatar, Laurel Green (`AppColors.outline`) once every story in the
/// group has been viewed, Moderate Green (`AppColors.primary`) while
/// at least one is unviewed. Purely presentational — callers pass the
/// already-computed flag (`StoryGroup.allViewed`) rather than this
/// widget reaching into providers itself.
class StoryRingAvatar extends StatelessWidget {
  const StoryRingAvatar({
    super.key,
    required this.avatarUrl,
    required this.hasUnviewed,
    this.size = 56,
    this.fallbackLabel,
  });

  final String? avatarUrl;
  final bool hasUnviewed;
  final double size;

  /// Shown instead of a broken-image icon when [avatarUrl] is null —
  /// typically the first letter of the display name/username.
  final String? fallbackLabel;

  @override
  Widget build(BuildContext context) {
    final ringColor = hasUnviewed ? AppColors.primary : AppColors.outline;
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: ringColor, width: 2),
      ),
      child: ClipOval(
        child: Container(
          color: AppColors.surfaceContainerHigh,
          child: avatarUrl != null
              ? Image.network(
                  avatarUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _fallback(context),
                )
              : _fallback(context),
        ),
      ),
    );
  }

  Widget _fallback(BuildContext context) {
    return Center(
      child: Text(
        (fallbackLabel?.isNotEmpty ?? false)
            ? fallbackLabel![0].toUpperCase()
            : '?',
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}
