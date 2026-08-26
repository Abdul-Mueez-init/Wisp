import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../core/theme/app_theme.dart';

/// Full-screen video playback, opened when a video message bubble is
/// tapped. Batch 5b — plain play/pause + scrubber, no extra chrome;
/// this is a demo app, not a video editor.
class VideoPlayerView extends StatefulWidget {
  const VideoPlayerView({super.key, required this.url});

  final String url;

  static Future<void> open(BuildContext context, String url) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => VideoPlayerView(url: url)),
    );
  }

  @override
  State<VideoPlayerView> createState() => _VideoPlayerViewState();
}

class _VideoPlayerViewState extends State<VideoPlayerView> {
  late final VideoPlayerController _controller;
  bool _initError = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() {});
        _controller.play();
      }).catchError((_) {
        if (!mounted) return;
        setState(() => _initError = true);
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: AppColors.cream),
      ),
      body: Center(
        child: _initError
            ? const Text('Could not load video.',
                style: TextStyle(color: AppColors.cream))
            : _controller.value.isInitialized
                ? AspectRatio(
                    aspectRatio: _controller.value.aspectRatio,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        VideoPlayer(_controller),
                        _PlayPauseOverlay(controller: _controller),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: VideoProgressIndicator(
                            _controller,
                            allowScrubbing: true,
                            colors: const VideoProgressColors(
                              playedColor: AppColors.primary,
                              bufferedColor: AppColors.outlineVariant,
                              backgroundColor: Colors.white24,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : const CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }
}

class _PlayPauseOverlay extends StatefulWidget {
  const _PlayPauseOverlay({required this.controller});
  final VideoPlayerController controller;

  @override
  State<_PlayPauseOverlay> createState() => _PlayPauseOverlayState();
}

class _PlayPauseOverlayState extends State<_PlayPauseOverlay> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTick);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTick);
    super.dispose();
  }

  void _onTick() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        widget.controller.value.isPlaying
            ? widget.controller.pause()
            : widget.controller.play();
      },
      child: AnimatedOpacity(
        opacity: widget.controller.value.isPlaying ? 0 : 1,
        duration: const Duration(milliseconds: 200),
        child: Container(
          color: Colors.black26,
          child: const Center(
            child: Icon(Icons.play_arrow_rounded,
                size: 64, color: AppColors.cream),
          ),
        ),
      ),
    );
  }
}
