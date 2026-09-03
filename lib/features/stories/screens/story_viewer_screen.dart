// lib/features/stories/screens/story_viewer_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format_utils.dart';
import '../../../models/story.dart';
import '../../auth/providers/auth_provider.dart';
import '../../profile/providers/profile_provider.dart';
import '../providers/story_provider.dart';
import '../widgets/story_viewer_row.dart';

/// Arguments for the `/status/view` route. [groups] is the full set of
/// author story-groups the viewer can swipe between — a single-item
/// list when opened from "My status", the full "others" list when
/// opened from a contact's row (see status_list_screen.dart) — and
/// [initialIndex] is which group to open on.
class StoryViewerArgs {
  const StoryViewerArgs({required this.groups, required this.initialIndex});
  final List<StoryGroup> groups;
  final int initialIndex;
}

const _kVideoExtensions = {'mp4', 'mov', 'm4v', 'webm', 'avi', '3gp'};

/// Fullscreen per-author story sequence (plan.md Phase 6, batch 6c).
/// Segmented progress bar per story, tap-through (left 30% = previous
/// story, right 70% = next), long-press to pause, horizontal swipe to
/// move between authors.
///
/// `stories` has no `type`/`is_video` column (ERD.md) — image vs. video
/// is inferred client-side from the media file extension rather than
/// adding a column for something derivable, consistent with this
/// phase's other "client-side, no schema change" calls (expiry, etc).
///
/// Scope trim per the handoff doc: no reply-to-story field, no
/// sticker/text-overlay editor — `caption` (already in ERD.md) is
/// rendered as a plain bottom-aligned overlay instead.
class StoryViewerScreen extends ConsumerStatefulWidget {
  const StoryViewerScreen({
    super.key,
    required this.groups,
    required this.initialIndex,
  });

  final List<StoryGroup> groups;
  final int initialIndex;

  @override
  ConsumerState<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends ConsumerState<StoryViewerScreen>
    with SingleTickerProviderStateMixin {
  static const _imageDuration = Duration(seconds: 5);
  static const _maxVideoDuration = Duration(seconds: 30);

  late List<StoryGroup> _groups;
  late int _groupIndex;
  int _storyIndex = 0;

  late final AnimationController _progress;
  VideoPlayerController? _videoController;
  final Set<String> _viewedThisSession = {};

  String? get _myId => ref.read(currentSessionProvider)?.user.id;

  @override
  void initState() {
    super.initState();
    // Defensive re-filter — a story could theoretically expire between
    // the Status list's fetch and this screen opening. Same "client-side
    // filter, no cron" reasoning as StoryRepository.fetchActiveStoryGroups.
    _groups = widget.groups
        .map((g) => StoryGroup(
              author: g.author,
              stories: g.stories.where((s) => !s.isExpired).toList(),
              viewedStoryIds: g.viewedStoryIds,
            ))
        .where((g) => g.stories.isNotEmpty)
        .toList();
    _groupIndex =
        widget.initialIndex.clamp(0, _groups.isEmpty ? 0 : _groups.length - 1);

    _progress = AnimationController(vsync: this)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _advance(forward: true);
      });

    if (_groups.isEmpty) {
      // Nothing left to show — bail out after first frame rather than
      // popping mid-build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    } else {
      _storyIndex = _firstUnviewedIndex(_groups[_groupIndex]);
      _loadStory();
    }
  }

  int _firstUnviewedIndex(StoryGroup group) {
    final idx =
        group.stories.indexWhere((s) => !group.viewedStoryIds.contains(s.id));
    return idx == -1 ? 0 : idx;
  }

  StoryGroup get _currentGroup => _groups[_groupIndex];
  Story get _currentStory => _currentGroup.stories[_storyIndex];

  bool _isVideo(String mediaUrl) {
    final ext = mediaUrl.split('.').last.toLowerCase().split('?').first;
    return _kVideoExtensions.contains(ext);
  }

  void _loadStory() {
    _progress.stop();
    _videoController?.dispose();
    _videoController = null;

    final story = _currentStory;
    final url = ref.read(storyMediaUrlProvider(story.mediaUrl));
    _recordView(story);

    if (_isVideo(story.mediaUrl)) {
      final controller = VideoPlayerController.networkUrl(Uri.parse(url));
      _videoController = controller;
      controller.initialize().then((_) {
        if (!mounted || _videoController != controller) return;
        final capped = controller.value.duration > _maxVideoDuration
            ? _maxVideoDuration
            : controller.value.duration;
        _progress.duration = capped == Duration.zero ? _imageDuration : capped;
        controller.play();
        _progress.forward(from: 0);
        setState(() {});
      }).catchError((_) {
        // Couldn't load the video — don't strand the viewer on a dead
        // story, just advance past it.
        if (mounted) _advance(forward: true);
      });
      setState(() {});
    } else {
      _progress.duration = _imageDuration;
      _progress.forward(from: 0);
      setState(() {});
    }
  }

  void _recordView(Story story) {
    final myId = _myId;
    if (myId == null) return;
    if (_currentGroup.author.id == myId) return; // don't log self-views
    if (!_viewedThisSession.add(story.id))
      return; // already recorded this session
    unawaited(
      ref
          .read(storyRepositoryProvider)
          .recordView(storyId: story.id, viewerId: myId)
          .catchError(
              (_) {}), // best-effort — a failed view log shouldn't crash the viewer
    );
  }

  void _advance({required bool forward}) {
    if (forward) {
      if (_storyIndex < _currentGroup.stories.length - 1) {
        setState(() => _storyIndex++);
        _loadStory();
      } else if (_groupIndex < _groups.length - 1) {
        setState(() {
          _groupIndex++;
          _storyIndex = _firstUnviewedIndex(_currentGroup);
        });
        _loadStory();
      } else {
        Navigator.of(context).pop();
      }
    } else {
      if (_storyIndex > 0) {
        setState(() => _storyIndex--);
        _loadStory();
      } else if (_groupIndex > 0) {
        setState(() {
          _groupIndex--;
          _storyIndex = _currentGroup.stories.length - 1;
        });
        _loadStory();
      } else {
        _loadStory(); // restart the first story rather than doing nothing
      }
    }
  }

  void _changeGroup(int delta) {
    final target = _groupIndex + delta;
    if (target < 0 || target >= _groups.length) return;
    setState(() {
      _groupIndex = target;
      _storyIndex = _firstUnviewedIndex(_currentGroup);
    });
    _loadStory();
  }

  void _pause() {
    _progress.stop();
    _videoController?.pause();
  }

  void _resume() {
    if (_videoController != null && !_videoController!.value.isInitialized)
      return;
    _progress.forward();
    _videoController?.play();
  }

  @override
  void dispose() {
    _progress.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_groups.isEmpty) {
      return const Scaffold(
          backgroundColor: Colors.black, body: SizedBox.shrink());
    }

    final story = _currentStory;
    final group = _currentGroup;
    final width = MediaQuery.of(context).size.width;
    // Part C (story viewer list): only the story's own author ever sees
    // the "who viewed this" pill — never on a story you're viewing that
    // belongs to someone else. That symmetric case (them seeing that
    // you viewed) is exactly what `recordView()` already, correctly,
    // quietly handles with no UI on your side.
    final isOwnStory = group.author.id == _myId;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) {
            if (details.globalPosition.dx < width * 0.3) {
              _advance(forward: false);
            } else {
              _advance(forward: true);
            }
          },
          onLongPressStart: (_) => _pause(),
          onLongPressEnd: (_) => _resume(),
          onHorizontalDragEnd: (details) {
            final velocity = details.primaryVelocity ?? 0;
            if (velocity < -200) {
              _changeGroup(1);
            } else if (velocity > 200) {
              _changeGroup(-1);
            }
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(child: _buildMedia(story)),
              // Combined bottom layer so the viewer-count pill and the
              // caption gradient never overlap — pill sits just above
              // the caption instead of both being independently pinned
              // to the same bottom edge.
              if (isOwnStory || (story.caption?.isNotEmpty ?? false))
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isOwnStory) _buildViewersPill(story),
                      if (story.caption?.isNotEmpty ?? false)
                        _buildCaptionContent(story),
                    ],
                  ),
                ),
              Positioned(
                top: 8,
                left: 8,
                right: 8,
                child: Column(
                  children: [
                    _buildProgressBar(group),
                    const SizedBox(height: 10),
                    _buildHeader(group, story),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMedia(Story story) {
    if (_isVideo(story.mediaUrl)) {
      final controller = _videoController;
      if (controller == null || !controller.value.isInitialized) {
        return const CircularProgressIndicator(
            strokeWidth: 2, color: AppColors.primary);
      }
      return AspectRatio(
        aspectRatio: controller.value.aspectRatio,
        child: VideoPlayer(controller),
      );
    }
    final url = ref.read(storyMediaUrlProvider(story.mediaUrl));
    return Image.network(
      url,
      fit: BoxFit.contain,
      width: double.infinity,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return const Center(
          child: CircularProgressIndicator(
              strokeWidth: 2, color: AppColors.primary),
        );
      },
      errorBuilder: (_, __, ___) => const Center(
        child: Icon(Icons.broken_image_outlined,
            color: AppColors.outline, size: 48),
      ),
    );
  }

  Widget _buildProgressBar(StoryGroup group) {
    return Row(
      children: [
        for (var i = 0; i < group.stories.length; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.full),
              child: SizedBox(
                height: 2.5,
                child: i < _storyIndex
                    ? const ColoredBox(color: AppColors.cream)
                    : i > _storyIndex
                        ? ColoredBox(color: AppColors.cream.withOpacity(0.3))
                        : AnimatedBuilder(
                            animation: _progress,
                            builder: (context, _) => LinearProgressIndicator(
                              value: _progress.value,
                              backgroundColor: AppColors.cream.withOpacity(0.3),
                              valueColor:
                                  const AlwaysStoppedAnimation(AppColors.cream),
                            ),
                          ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildHeader(StoryGroup group, Story story) {
    final avatarPath = group.author.avatarUrl;
    final avatarUrl = avatarPath != null
        ? ref.read(profileRepositoryProvider).resolveAvatarUrl(avatarPath)
        : null;
    final name = group.author.displayName ?? group.author.username;

    return Row(
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: AppColors.surfaceContainerHigh,
          backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
          child: avatarUrl == null
              ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: const TextStyle(color: AppColors.cream, fontSize: 13))
              : null,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(name,
                  style: const TextStyle(
                      color: AppColors.cream, fontWeight: FontWeight.w500)),
              Text(formatRelativeShort(story.createdAt),
                  style: TextStyle(
                      color: AppColors.cream.withOpacity(0.7), fontSize: 12)),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close, color: AppColors.cream),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  // Renamed from _buildCaptionOverlay: no longer wraps itself in its own
  // `Positioned` — it's now one child inside the shared bottom `Column`
  // in `build()` (alongside the viewers pill), so a `Positioned` here
  // would be invalid (Positioned only works as a direct Stack child).
  Widget _buildCaptionContent(Story story) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.pageMargin, 40, AppSpacing.pageMargin, 28),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black87],
        ),
      ),
      child: Text(
        story.caption!,
        style: const TextStyle(color: AppColors.cream, fontSize: 15),
      ),
    );
  }

  /// Part C — the tappable "N views" pill shown only to the story's own
  /// author. Wrapped in its own `Consumer` so watching
  /// `storyViewersProvider` (for the live count) doesn't rebuild the
  /// whole screen — just this small pill.
  Widget _buildViewersPill(Story story) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Consumer(
        builder: (context, ref, _) {
          final viewersAsync = ref.watch(storyViewersProvider(story.id));
          final count = viewersAsync.valueOrNull?.length;
          return Center(
            child: GestureDetector(
              onTap: () => _openViewersSheet(story),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.remove_red_eye_outlined,
                        color: AppColors.cream, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      count == null
                          ? 'Viewers'
                          : '$count ${count == 1 ? 'view' : 'views'}',
                      style: const TextStyle(
                        color: AppColors.cream,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Opens the "Viewed by" bottom sheet. Pauses the story's own
  /// auto-advance timer/video first (same "don't let the story
  /// auto-advance while the person is reading something on top of it"
  /// behavior long-press already gives you) and resumes exactly where
  /// it left off when the sheet closes.
  void _openViewersSheet(Story story) {
    _pause();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceContainer,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (sheetContext) => _StoryViewersSheet(storyId: story.id),
    ).whenComplete(() {
      if (mounted) _resume();
    });
  }
}

/// Bottom sheet body for the "Viewed by" list — most-recent-view-first,
/// avatar + name + relative timestamp per row, loading/error/empty
/// states. One-shot `FutureProvider.family` per `storyViewersProvider`'s
/// doc comment — it's a snapshot, not a live-updating list.
class _StoryViewersSheet extends ConsumerWidget {
  const _StoryViewersSheet({required this.storyId});

  final String storyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewersAsync = ref.watch(storyViewersProvider(storyId));

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.onSurfaceVariant.withOpacity(0.4),
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.pageMargin, 16, AppSpacing.pageMargin, 8),
              child: Row(
                children: [
                  const Icon(Icons.remove_red_eye_outlined,
                      color: AppColors.cream, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    viewersAsync.valueOrNull == null
                        ? 'Viewed by'
                        : 'Viewed by ${viewersAsync.value!.length}',
                    style: const TextStyle(
                      color: AppColors.cream,
                      fontWeight: FontWeight.w500,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.outlineVariant),
            Flexible(
              child: viewersAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.primary),
                  ),
                ),
                error: (error, _) => Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Could not load viewers.',
                        style: TextStyle(color: AppColors.onSurfaceVariant),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () =>
                            ref.invalidate(storyViewersProvider(storyId)),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
                data: (viewers) {
                  if (viewers.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(
                        child: Text(
                          'No views yet',
                          style: TextStyle(color: AppColors.onSurfaceVariant),
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: 16, top: 8),
                    itemCount: viewers.length,
                    itemBuilder: (context, index) =>
                        StoryViewerRow(viewer: viewers[index]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
