// lib/features/voice_notes/providers/voice_note_provider.dart
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart' show Amplitude;

import '../data/voice_note_repository.dart';

enum VoiceRecordingPhase { idle, recording, cancelling }

class VoiceRecordingState {
  const VoiceRecordingState({
    this.phase = VoiceRecordingPhase.idle,
    this.elapsed = Duration.zero,
  });

  final VoiceRecordingPhase phase;
  final Duration elapsed;

  VoiceRecordingState copyWith({
    VoiceRecordingPhase? phase,
    Duration? elapsed,
  }) {
    return VoiceRecordingState(
      phase: phase ?? this.phase,
      elapsed: elapsed ?? this.elapsed,
    );
  }
}

class VoiceRecordingResult {
  const VoiceRecordingResult({this.bytes, required this.duration});
  final Uint8List? bytes;
  final Duration duration;
}

/// Owns the recording *session* lifecycle (start / drag-to-cancel /
/// stop) — the actual upload + `messages` insert happens through
/// `SendMediaMessageController` in `chat/providers/message_provider.dart`,
/// same as image/video/document, keeping the existing Phase 5a/5b split
/// between "capture" and "send" intact.
class VoiceRecordingController extends Notifier<VoiceRecordingState> {
  late final VoiceNoteRepository _repository;
  Timer? _ticker;

  @override
  VoiceRecordingState build() {
    _repository = VoiceNoteRepository();
    ref.onDispose(() {
      _ticker?.cancel();
      _repository.dispose();
    });
    return const VoiceRecordingState();
  }

  Stream<Amplitude> get amplitudeStream => _repository.amplitudeStream();

  /// Throws [ValidationFailure] (from core/errors) if mic permission is
  /// denied — left uncaught so the UI (`VoiceRecordButton`) surfaces it.
  Future<void> start() async {
    if (state.phase != VoiceRecordingPhase.idle) return;
    await _repository.start();
    state = const VoiceRecordingState(phase: VoiceRecordingPhase.recording);
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      state = state.copyWith(
        elapsed: state.elapsed + const Duration(milliseconds: 200),
      );
    });
  }

  void markCancelling(bool cancelling) {
    if (state.phase == VoiceRecordingPhase.idle) return;
    final phase = cancelling
        ? VoiceRecordingPhase.cancelling
        : VoiceRecordingPhase.recording;
    if (phase == state.phase) return;
    state = state.copyWith(phase: phase);
  }

  /// Stops the recorder and returns the captured bytes (null bytes if
  /// the gesture ended in "slide to cancel" or nothing was captured).
  Future<VoiceRecordingResult> stopAndGetBytes() async {
    final elapsed = state.elapsed;
    final wasCancelling = state.phase == VoiceRecordingPhase.cancelling;
    _ticker?.cancel();
    state = const VoiceRecordingState();
    if (wasCancelling) {
      await _repository.cancel();
      return VoiceRecordingResult(duration: elapsed);
    }
    final bytes = await _repository.stop();
    return VoiceRecordingResult(bytes: bytes, duration: elapsed);
  }

  Future<void> cancelRecording() async {
    _ticker?.cancel();
    state = const VoiceRecordingState();
    await _repository.cancel();
  }
}

final voiceRecordingControllerProvider =
    NotifierProvider<VoiceRecordingController, VoiceRecordingState>(
  VoiceRecordingController.new,
);
