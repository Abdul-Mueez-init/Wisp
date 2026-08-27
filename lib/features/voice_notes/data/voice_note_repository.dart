// lib/features/voice_notes/data/voice_note_repository.dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:record/record.dart';

import '../../../core/errors/failure.dart';

/// Wraps the `record` package for mic capture only — playback is a
/// separate concern handled by `just_audio` directly inside
/// `voice_note_bubble.dart` (Batch 5c decision: neither package does
/// both capture and playback well, so `record` for capture / `just_audio`
/// for playback, both actively maintained). Records to a temp file
/// (the package's stream-to-bytes API isn't consistent across
/// platforms yet) and reads it back to bytes once stopped; the temp
/// file is deleted immediately after either a successful read or a
/// cancel — nothing lingers on disk.
class VoiceNoteRepository {
  VoiceNoteRepository() : _recorder = AudioRecorder();

  final AudioRecorder _recorder;

  /// `record`'s own permission flow — no separate `permission_handler`
  /// dependency needed for this one permission.
  Future<bool> hasPermission() => _recorder.hasPermission();

  /// Mic level updates while recording, used for the live indicator in
  /// `chat_input_bar.dart`'s recording row.
  Stream<Amplitude> amplitudeStream() =>
      _recorder.onAmplitudeChanged(const Duration(milliseconds: 150));

  Future<void> start() async {
    final granted = await hasPermission();
    if (!granted) {
      throw const ValidationFailure(
        'Microphone permission is required to record a voice note.',
      );
    }
    final path =
        '${Directory.systemTemp.path}/wisp_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 64000,
        sampleRate: 44100,
        numChannels: 1,
      ),
      path: path,
    );
  }

  /// Stops recording and returns the captured bytes, or null if
  /// nothing usable was captured.
  Future<Uint8List?> stop() async {
    final path = await _recorder.stop();
    if (path == null) return null;
    final file = File(path);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    unawaited(file.delete().catchError((_) => file));
    return bytes.isEmpty ? null : bytes;
  }

  /// Discards the in-progress recording without returning bytes — the
  /// "slide to cancel" gesture.
  Future<void> cancel() async {
    final path = await _recorder.stop();
    if (path == null) return;
    final file = File(path);
    if (await file.exists()) {
      await file.delete().catchError((_) => file);
    }
  }

  void dispose() => _recorder.dispose();
}
