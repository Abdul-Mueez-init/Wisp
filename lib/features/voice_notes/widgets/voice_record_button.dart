// lib/features/voice_notes/widgets/voice_record_button.dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/voice_note_provider.dart';

/// Press-and-hold mic button, WhatsApp-style: hold to record, release
/// to send, drag left past the cancel threshold to discard. Sits in
/// the same slot as [ChatInputBar]'s send button — swapped in by
/// `chat_input_bar.dart` whenever the text field is empty, so the
/// user's thumb never has to move between typing and recording.
class VoiceRecordButton extends ConsumerStatefulWidget {
  const VoiceRecordButton({
    super.key,
    required this.onRecorded,
    required this.enabled,
  });

  /// Called with the recorded bytes once a genuine (non-cancelled,
  /// non-accidental-tap) recording is released.
  final Future<void> Function(Uint8List bytes) onRecorded;
  final bool enabled;

  @override
  ConsumerState<VoiceRecordButton> createState() => _VoiceRecordButtonState();
}

class _VoiceRecordButtonState extends ConsumerState<VoiceRecordButton> {
  static const _cancelThreshold = -80.0;
  static const _minRecordDuration = Duration(milliseconds: 400);

  VoiceRecordingController get _controller =>
      ref.read(voiceRecordingControllerProvider.notifier);

  Future<void> _start() async {
    if (!widget.enabled) return;
    try {
      await _controller.start();
    } on Failure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _onMove(LongPressMoveUpdateDetails details) {
    if (ref.read(voiceRecordingControllerProvider).phase ==
        VoiceRecordingPhase.idle) {
      return;
    }
    _controller.markCancelling(details.offsetFromOrigin.dx < _cancelThreshold);
  }

  Future<void> _end() async {
    final wasIdle = ref.read(voiceRecordingControllerProvider).phase ==
        VoiceRecordingPhase.idle;
    if (wasIdle) return;
    final result = await _controller.stopAndGetBytes();
    if (result.bytes == null) return; // cancelled or nothing captured
    if (result.duration < _minRecordDuration) return; // accidental tap
    await widget.onRecorded(result.bytes!);
  }

  Future<void> _cancel() => _controller.cancelRecording();

  @override
  Widget build(BuildContext context) {
    final phase = ref.watch(voiceRecordingControllerProvider).phase;
    final recording = phase != VoiceRecordingPhase.idle;
    final cancelling = phase == VoiceRecordingPhase.cancelling;

    return GestureDetector(
      onLongPressStart: (_) => _start(),
      onLongPressMoveUpdate: _onMove,
      onLongPressEnd: (_) => _end(),
      onLongPressCancel: _cancel,
      child: AnimatedScale(
        scale: recording ? 1.15 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: cancelling ? AppColors.error : AppColors.primaryContainer,
          ),
          child: Icon(
            cancelling ? Icons.delete_outline : Icons.mic_none_rounded,
            color: AppColors.cream,
          ),
        ),
      ),
    );
  }
}
