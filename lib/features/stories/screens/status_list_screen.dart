// lib/features/stories/screens/status_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format_utils.dart';
import '../../../models/story.dart';
import '../../auth/providers/auth_provider.dart';
import '../../profile/providers/profile_provider.dart';
import '../providers/story_provider.dart';
import '../widgets/story_ring_avatar.dart';

/// Status tab (plan.md Phase 6, batch 6b). Per design.md's Stitch
/// export, grouped into "My status" / "Recent updates" / "Viewed
/// updates". Tapping another user's row would open the full-screen
/// story viewer — that's 6c, not built yet, so rows are tappable but
/// surface a plain "coming in 6c" notice rather than faking a viewer.
class StatusListScreen extends ConsumerWidget {
  const StatusListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myId = ref.watch(currentSessionProvider)?.user.id;
    final groupsAsync = ref.watch(activeStoryGroupsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Status')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(activeStoryGroupsProvider.future),
        child: groupsAsync.when(
          loading: () =>
              const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.pageMargin),
              child: Text('$e', style: const TextStyle(color: AppColors.error)),
            ),
          ),
          data: (groups) {
            StoryGroup? myGroup;
            if (myId != null) {
              for (final g in groups) {
                if (g.author.id == myId) {
                  myGroup = g;
                  break;
                }
              }
            }
            final others = groups.where((g) => g.author.id != myId).toList();
            final unviewed = others.where((g) => !g.allViewed).toList();
            final viewed = others.where((g) => g.allViewed).toList();

            return ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                const _SectionLabel('My status'),
                _MyStatusTile(group: myGroup),
                if (unviewed.isNotEmpty) ...[
                  const _SectionLabel('Recent updates'),
                  for (final g in unviewed) _StatusTile(group: g),
                ],
                if (viewed.isNotEmpty) ...[
                  const _SectionLabel('Viewed updates'),
                  for (final g in viewed) _StatusTile(group: g),
                ],
                if (others.isEmpty && myGroup == null)
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.pageMargin),
                    child: Text(
                      'No status updates yet. Be the first — tap "My status" above.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MyStatusTile extends ConsumerWidget {
  const _MyStatusTile({required this.group});
  final StoryGroup? group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myProfileAsync = ref.watch(currentProfileProvider);
    final hasStory = group != null && group!.stories.isNotEmpty;

    return myProfileAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (myProfile) {
        final avatarUrl = myProfile?.avatarUrl != null
            ? ref
                .read(profileRepositoryProvider)
                .resolveAvatarUrl(myProfile!.avatarUrl!)
            : null;
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.pageMargin, vertical: 4),
          leading: Stack(
            clipBehavior: Clip.none,
            children: [
              StoryRingAvatar(
                avatarUrl: avatarUrl,
                hasUnviewed: hasStory && !group!.allViewed,
                fallbackLabel: myProfile?.displayName ?? myProfile?.username,
              ),
              if (!hasStory)
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primaryContainer,
                    ),
                    child:
                        const Icon(Icons.add, size: 14, color: AppColors.cream),
                  ),
                ),
            ],
          ),
          title: const Text('My status'),
          subtitle: Text(
            hasStory
                ? '${group!.stories.length} update${group!.stories.length > 1 ? 's' : ''} · tap to add another'
                : 'Tap to add a status update',
          ),
          onTap: () => context.push('/status/new'),
        );
      },
    );
  }
}

class _StatusTile extends ConsumerWidget {
  const _StatusTile({required this.group});
  final StoryGroup group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final avatarPath = group.author.avatarUrl;
    final avatarUrl = avatarPath != null
        ? ref.read(profileRepositoryProvider).resolveAvatarUrl(avatarPath)
        : null;
    final name = group.author.displayName ?? group.author.username;
    final latest = group.latest;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.pageMargin, vertical: 4),
      leading: StoryRingAvatar(
        avatarUrl: avatarUrl,
        hasUnviewed: !group.allViewed,
        fallbackLabel: name,
      ),
      title: Text(name),
      subtitle: Text(
        (latest.caption?.isNotEmpty ?? false)
            ? latest.caption!
            : formatChatTimestamp(latest.createdAt),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Full story viewer is coming in batch 6c.'),
          ),
        );
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.pageMargin, 16, AppSpacing.pageMargin, 4),
      child: Text(label, style: Theme.of(context).textTheme.labelMedium),
    );
  }
}
