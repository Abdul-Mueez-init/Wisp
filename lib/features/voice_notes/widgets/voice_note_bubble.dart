// lib/features/voice_notes/widgets/voice_note_bubble.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/message.dart';
import '../../chat/providers/message_provider.dart';

/// Playback bubble per the Stitch "voice_note_with_transcript" export:
/// a filled play/pause circle, a waveform, and a duration label.
/// Batch 5c ships play/pause + duration only — the "View Transcript" /
/// "Add to reminders" rows on that same screen are AI Feature 3
/// (Phase 9), not this batch, and are deliberately not stubbed here
/// (no phantom feature scaffolding, per rules.md Rule 2).
///
/// No waveform-analysis package is used (would add a native dependency
/// for one cosmetic detail, same reasoning as the video bubble's flat
/// play-button cover in Batch 5b) — bars are a deterministic
/// pseudo-pattern seeded by the message id, with the played portion
/// highlighted in the primary color.
class VoiceNoteBubble extends ConsumerStatefulWidget {
  const VoiceNoteBubble(
      {super.key, required this.message, required this.isMine});

  final Message message;
  final bool isMine;

  @override
  ConsumerState<VoiceNoteBubble> createState() => _VoiceNoteBubbleState();
}

class _VoiceNoteBubbleState extends ConsumerState<VoiceNoteBubble> {
  final _player = AudioPlayer();
  String? _loadedUrl;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _ensureLoaded(String url) async {
    if (_loadedUrl == url) return;
    _loadedUrl = url;
    try {
      await _player.setUrl(url);
    } catch (_) {
      _loadedUrl = null;
    }
  }

  Future<void> _togglePlay(ProcessingState? state) async {
    if (_player.playing) {
      await _player.pause();
      return;
    }
    if (state == ProcessingState.completed) await _player.seek(Duration.zero);
    await _player.play();
  }

  @override
  Widget build(BuildContext context) {
    final path = widget.message.mediaUrl;
    final textColor = widget.isMine ? AppColors.cream : AppColors.onSurface;

    if (path == null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.mic_off_outlined, size: 18, color: textColor),
          const SizedBox(width: 8),
          Text('Voice note unavailable',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: textColor, fontStyle: FontStyle.italic)),
        ],
      );
    }

    final urlAsync = ref.watch(mediaSignedUrlProvider(path));

    return urlAsync.when(
      data: (url) {
        _ensureLoaded(url);
        return StreamBuilder<PlayerState>(
          stream: _player.playerStateStream,
          builder: (context, snapshot) {
            final playing = snapshot.data?.playing ?? false;
            final processingState = snapshot.data?.processingState;
            final isBuffering = processingState == ProcessingState.loading ||
                processingState == ProcessingState.buffering;

            return SizedBox(
              height: 40,
              child: Row(
                children: [
                  _PlayButton(
                    playing: playing,
                    loading: isBuffering,
                    onTap: () => _togglePlay(processingState),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StreamBuilder<Duration>(
                      stream: _player.positionStream,
                      builder: (context, posSnap) {
                        final position = posSnap.data ?? Duration.zero;
                        final duration = _player.duration ?? Duration.zero;
                        final progress = duration.inMilliseconds == 0
                            ? 0.0
                            : (position.inMilliseconds /
                                    duration.inMilliseconds)
                                .clamp(0.0, 1.0);
                        return _Waveform(
                          seed: widget.message.id,
                          progress: progress,
                          color: textColor,
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  StreamBuilder<Duration?>(
                    stream: _player.durationStream,
                    builder: (context, durSnap) {
                      final total = durSnap.data ?? _player.duration;
                      return Text(
                        _formatDuration(total),
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: textColor),
                      );
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
      loading: () => const SizedBox(
        height: 40,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (e, _) => Text(
        'Could not load voice note',
        style:
            Theme.of(context).textTheme.bodyMedium?.copyWith(color: textColor),
      ),
    );
  }

  String _formatDuration(Duration? d) {
    if (d == null || d == Duration.zero) return '--:--';
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({
    required this.playing,
    required this.loading,
    required this.onTap,
  });

  final bool playing;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.primaryContainer,
        ),
        child: loading
            ? const Padding(
                padding: EdgeInsets.all(10),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.cream,
                ),
              )
            : Icon(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: AppColors.cream,
              ),
      ),
    );
  }
}

class _Waveform extends StatelessWidget {
  const _Waveform({
    required this.seed,
    required this.progress,
    required this.color,
  });

  final String seed;
  final double progress;
  final Color color;

  static const _barCount = 24;

  @override
  Widget build(BuildContext context) {
    final heights = _pseudoWaveform(seed, _barCount);
    return LayoutBuilder(
      builder: (context, constraints) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(_barCount, (i) {
            final playedIndex = (progress * _barCount).floor();
            final isPlayed = i <= playedIndex;
            return Container(
              width: 2.5,
              height: 6 + (heights[i] * 18),
              decoration: BoxDecoration(
                color: color.withValues(alpha: isPlayed ? 1.0 : 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        );
      },
    );
  }

  List<double> _pseudoWaveform(String seed, int barCount) {
    var h = seed.hashCode;
    return List.generate(barCount, (i) {
      h = (h * 1103515245 + 12345) & 0x7fffffff;
      return 0.3 + (h % 100) / 100 * 0.7;
    });
  }
}
