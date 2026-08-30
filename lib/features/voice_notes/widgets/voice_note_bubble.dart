// lib/features/voice_notes/widgets/voice_note_bubble.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/message.dart';
import '../../chat/providers/message_provider.dart';
import '../data/voice_transcription_repository.dart';

/// Playback bubble per the Stitch "voice_note_with_transcript" export:
/// a filled play/pause circle, a waveform, and a duration label, plus
/// (Phase 9, once `messages.voice_transcript` is populated) an
/// expandable "View transcript" row and an "Add to reminders" chip
/// when the AI extracted at least one action item. Both are omitted
/// entirely — not shown as loading/empty states — until the
/// fire-and-forget transcription pipeline in `message_provider.dart`
/// finishes and the realtime stream carries the update in, same
/// "silent until ready" behavior Phase 7 established for translation.
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
  bool _transcriptExpanded = false;

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
    final transcript = widget.message.voiceTranscript;
    final hasTranscript = transcript != null && transcript.trim().isNotEmpty;
    final actions = _parseActions(widget.message.voiceActions);

    final playbackRow = urlAsync.when(
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

    if (!hasTranscript && actions.isEmpty) return playbackRow;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        playbackRow,
        if (hasTranscript) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Divider(
              height: 1,
              thickness: 1,
              color: textColor.withValues(alpha: 0.12),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _TranscriptToggle(
              expanded: _transcriptExpanded,
              textColor: textColor,
              onTap: () =>
                  setState(() => _transcriptExpanded = !_transcriptExpanded),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeInOut,
            alignment: Alignment.topLeft,
            child: _transcriptExpanded
                ? Padding(
                    padding: const EdgeInsets.only(top: 6, right: 4),
                    child: Text(
                      // Safe: this branch only builds when
                      // hasTranscript is true, which already
                      // guarantees transcript is non-null — Dart's
                      // flow analysis promotes it in this scope, so
                      // no `!` is needed here.
                      transcript,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: textColor.withValues(alpha: 0.85),
                            height: 1.4,
                          ),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
        if (actions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _AddToRemindersChip(
              actions: actions,
              onTap: () => _showActionsSheet(context, actions),
            ),
          ),
      ],
    );
  }

  List<VoiceActionItem> _parseActions(Map<String, dynamic>? raw) {
    final items = raw?['items'] as List<dynamic>?;
    if (items == null) return const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(VoiceActionItem.fromJson)
        .toList();
  }

  /// "Add to reminders" tap target — this app has no calendar/reminders
  /// integration (no such dependency, table, or architecture piece per
  /// architecture.md), so per rules.md Rule 1 this deliberately doesn't
  /// pretend to write anywhere real. It surfaces exactly what PRD.md
  /// §10 asks for — "extracted actions... shown attached to the voice
  /// note message" — as a clear, honest read-only sheet rather than a
  /// fake integration.
  Future<void> _showActionsSheet(
    BuildContext context,
    List<VoiceActionItem> actions,
  ) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppColors.outline.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                  ),
                ),
                Row(
                  children: [
                    const Icon(Icons.auto_awesome,
                        size: 18, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Text(
                      'From this voice note',
                      style: Theme.of(sheetContext).textTheme.titleMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  "Wisp picked these up automatically — nothing is saved "
                  "anywhere yet.",
                  style: Theme.of(sheetContext).textTheme.labelSmall,
                ),
                const SizedBox(height: 16),
                ...actions.map(
                  (a) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(Icons.check_circle_outline,
                              size: 18, color: AppColors.primary),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                a.title,
                                style:
                                    Theme.of(sheetContext).textTheme.bodyLarge,
                              ),
                              if (a.time != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    a.time!,
                                    style: Theme.of(sheetContext)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(color: AppColors.primary),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatDuration(Duration? d) {
    if (d == null || d == Duration.zero) return '--:--';
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

/// The "View transcript" expandable row — chevron rotates on toggle,
/// per the Stitch `<details>`/`<summary>` treatment. Collapsed by
/// default; [onTap] is owned by the parent state so it can drive the
/// `AnimatedSize` wrapping the actual transcript text.
class _TranscriptToggle extends StatelessWidget {
  const _TranscriptToggle({
    required this.expanded,
    required this.textColor,
    required this.onTap,
  });

  final bool expanded;
  final Color textColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final labelColor = textColor.withValues(alpha: 0.75);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Row(
        children: [
          Icon(Icons.subtitles_outlined, size: 16, color: labelColor),
          const SizedBox(width: 6),
          Text(
            'View transcript',
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: labelColor),
          ),
          const Spacer(),
          AnimatedRotation(
            turns: expanded ? 0.5 : 0,
            duration: const Duration(milliseconds: 180),
            child: Icon(Icons.expand_more, size: 18, color: labelColor),
          ),
        ],
      ),
    );
  }
}

/// AI Feature 3's suggested-action chip, per the Stitch "sparkle
/// pill" treatment — a hairline `primary`-tinted pill, tapped to open
/// the read-only actions sheet (see `_showActionsSheet`).
class _AddToRemindersChip extends StatelessWidget {
  const _AddToRemindersChip({required this.actions, required this.onTap});

  final List<VoiceActionItem> actions;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.full),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome, size: 14, color: AppColors.primary),
            const SizedBox(width: 6),
            Text(
              actions.length == 1
                  ? 'Add to reminders'
                  : 'Add ${actions.length} to reminders',
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: AppColors.cream),
            ),
          ],
        ),
      ),
    );
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
