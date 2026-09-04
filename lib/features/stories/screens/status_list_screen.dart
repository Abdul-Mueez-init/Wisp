// lib/features/stories/screens/status_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/layout_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format_utils.dart';
import '../../../models/story.dart';
import '../../auth/providers/auth_provider.dart';
import '../../profile/providers/profile_provider.dart';
import '../providers/story_provider.dart';
import '../widgets/story_ring_avatar.dart';
import 'story_viewer_screen.dart';
import '../../../widgets/error_state_view.dart';

/// Status tab (plan.md Phase 6, batches 6b/6c). Per design.md's Stitch
/// export, grouped into "My status" / "Recent updates" / "Viewed
/// updates". Tapping a row with a story now opens the fullscreen
/// viewer (batch 6c) instead of the 6b placeholder snackbar.
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
          // Phase 11 polish: friendly copy + explicit retry, instead of
          // the raw exception. Pull-to-refresh (RefreshIndicator above)
          // already covers this, but a persistent error state with no
          // affordance at all reads as broken rather than "swipe down".
          error: (e, _) => ErrorStateView(
            error: e,
            onRetry: () => ref.refresh(activeStoryGroupsProvider),
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
              // Jazz-World glass-nav pass: extra trailing space so the
              // last row can scroll clear of AppShell's floating pill
              // nav (now `extendBody: true`, real content behind it).
              padding: const EdgeInsets.only(
                top: 8,
                bottom: 8 + kFloatingNavClearance,
              ),
              children: [
                const _SectionLabel('My status'),
                _MyStatusTile(group: myGroup),
                if (unviewed.isNotEmpty) ...[
                  const _SectionLabel('Recent updates'),
                  for (final g in unviewed)
                    _StatusTile(group: g, allGroups: others),
                ],
                if (viewed.isNotEmpty) ...[
                  const _SectionLabel('Viewed updates'),
                  for (final g in viewed)
                    _StatusTile(group: g, allGroups: others),
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
              // Batch 6c fix: this used to only render when there was
              // no story yet, leaving no real way to post a second one
              // (the subtitle said "tap to add another" but the tile's
              // only onTap now correctly opens the viewer). It's its
              // own tap target now, always present, same as WhatsApp.
              Positioned(
                right: -2,
                bottom: -2,
                child: GestureDetector(
                  onTap: () => context.push('/status/new'),
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
              ),
            ],
          ),
          title: const Text('My status'),
          subtitle: Text(
            hasStory
                ? '${group!.stories.length} update${group!.stories.length > 1 ? 's' : ''} · tap to view'
                : 'Tap to add a status update',
          ),
          onTap: () async {
            if (!hasStory) {
              context.push('/status/new');
              return;
            }
            await context.push(
              '/status/view',
              extra: StoryViewerArgs(groups: [group!], initialIndex: 0),
            );
            ref.invalidate(activeStoryGroupsProvider);
          },
        );
      },
    );
  }
}

class _StatusTile extends ConsumerWidget {
  const _StatusTile({required this.group, required this.allGroups});
  final StoryGroup group;
  final List<StoryGroup> allGroups;

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
      onTap: () async {
        // Pass the full "others" list so a horizontal swipe inside the
        // viewer moves between authors, starting on the one tapped.
        final index = allGroups.indexOf(group);
        await context.push(
          '/status/view',
          extra: StoryViewerArgs(
              groups: allGroups, initialIndex: index < 0 ? 0 : index),
        );
        ref.invalidate(activeStoryGroupsProvider);
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
