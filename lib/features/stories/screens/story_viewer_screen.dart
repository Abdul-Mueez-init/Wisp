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
              if (story.caption?.isNotEmpty ?? false)
                _buildCaptionOverlay(story),
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

  Widget _buildCaptionOverlay(Story story) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
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
      ),
    );
  }
}
