import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

/// The looping "beep… beep…" tone played from the moment a call starts
/// dialing/ringing until it's answered (or cancelled/declined/ends).
/// Generates its own WAV file in temporary cache storage via a sine-wave synth.
///
/// Configured with:
/// - `handleInterruptions: false` so WebRTC microphone acquisition (MODE_IN_COMMUNICATION)
///   does not pause or duck this player.
/// - `handleAudioSessionActivation: false` so just_audio does not fight WebRTC's
///   audio session lifecycle.
/// - `androidApplyAudioAttributes: false` so global audio session changes do not
///   overwrite the dedicated signaling/ringtone attributes configured on this player.
/// - File-based playback (`setFilePath`) to avoid Android 9+ cleartext HTTP proxy restrictions.
enum _ToneType {
  dialTone,
  ringtone,
}

class CallSoundPlayer {
  CallSoundPlayer()
      : _player = AudioPlayer(
          handleInterruptions: false,
          handleAudioSessionActivation: false,
          androidApplyAudioAttributes: false,
        );

  final AudioPlayer _player;
  _ToneType? _loadedToneType;
  bool _playing = false;

  /// The last state actually requested (by CallController's phase
  /// changes), independent of how far the in-flight operation has
  /// gotten. `_run` checks this before its final `.play()`/pause so a
  /// start() immediately followed by a stop() (or vice versa) always
  /// resolves to what was most recently asked for — never to whichever
  /// async call happened to finish last.
  bool _desiredPlaying = false;
  _ToneType _desiredToneType = _ToneType.dialTone;

  /// Single FIFO queue ensuring start()/stop() requests always run in
  /// the order requested, never overlapping or finishing out of order.
  Future<void> _queue = Future.value();

  Future<void> _enqueue(Future<void> Function() op) {
    final result = _queue.then((_) => op());
    _queue = result.catchError((_) {});
    return result;
  }

  static const _sampleRate = 44100;

  Future<void> _ensureReady(_ToneType type) async {
    if (_loadedToneType == type) return;

    final tempDir = Directory.systemTemp;
    if (type == _ToneType.ringtone) {
      // Incoming ringtone: must play loud through the loudspeaker
      // with standard notification/ringtone audio attributes.
      await _player.setAndroidAudioAttributes(const AndroidAudioAttributes(
        usage: AndroidAudioUsage.notificationRingtone,
        contentType: AndroidAudioContentType.music,
      ));
      await _player.setVolume(1.0);
      final file = File('${tempDir.path}/wisp_ringtone.wav');
      if (!await file.exists() || await file.length() == 0) {
        final bytes = _buildRingtoneWav();
        await file.writeAsBytes(bytes, flush: true);
      }
      await _player.setFilePath(file.path);
    } else {
      // Outgoing dial/ringback tone: must be tagged as voiceCommunicationSignalling
      // so it is routed to the active communication audio stream (speakerphone)
      // without being ducked or muted by WebRTC's MODE_IN_COMMUNICATION.
      await _player.setAndroidAudioAttributes(const AndroidAudioAttributes(
        usage: AndroidAudioUsage.voiceCommunicationSignalling,
        contentType: AndroidAudioContentType.sonification,
      ));
      await _player.setVolume(1.0);
      final file = File('${tempDir.path}/wisp_dialtone.wav');
      if (!await file.exists() || await file.length() == 0) {
        final bytes = _buildDialToneWav();
        await file.writeAsBytes(bytes, flush: true);
      }
      await _player.setFilePath(file.path);
    }

    await _player.setLoopMode(LoopMode.one);
    _loadedToneType = type;
  }

  /// Requests the outgoing dial/ringback tone (clear dual-frequency beep cadence).
  Future<void> startDialTone() => _requestPlay(_ToneType.dialTone);

  /// Requests the incoming ringtone (loud melodic chime).
  Future<void> startRingtone() => _requestPlay(_ToneType.ringtone);

  /// Legacy alias: defaults to dial tone.
  Future<void> start() => startDialTone();

  Future<void> _requestPlay(_ToneType type) {
    _desiredPlaying = true;
    _desiredToneType = type;
    return _enqueue(() async {
      if (!_desiredPlaying) return;
      if (_playing && _loadedToneType == _desiredToneType) return;
      try {
        debugPrint('CallSoundPlayer: starting ${_desiredToneType.name} tone...');
        await _ensureReady(_desiredToneType);
        if (!_desiredPlaying) return;
        await _player.seek(Duration.zero);
        if (!_desiredPlaying) {
          await _safePause();
          return;
        }
        _playing = true;
        await _player.play();
        debugPrint('CallSoundPlayer: ${_desiredToneType.name} tone is playing');
      } catch (e, st) {
        debugPrint('CallSoundPlayer error playing tone: $e\n$st');
        _playing = false;
      }
    });
  }

  /// Requests the tone stop and rewind.
  Future<void> stop() {
    _desiredPlaying = false;
    return _enqueue(() async {
      if (!_playing) return;
      _playing = false;
      await _safePause();
    });
  }

  Future<void> _safePause() async {
    try {
      await _player.pause();
      await _player.seek(Duration.zero);
    } catch (_) {}
  }

  Future<void> dispose() async {
    _desiredPlaying = false;
    _playing = false;
    try {
      await _player.dispose();
    } catch (_) {}
  }

  /// Synthesizes a standard dual-frequency telephone ringback tone
  /// (440Hz + 480Hz, 0.4s beep + 0.2s pause + 0.4s beep + 2.0s pause, ~3s loop)
  /// for outgoing dial tone. Auditory clarity is prioritized so it is
  /// unmistakable over the loudspeaker.
  static Uint8List _buildDialToneWav() {
    const sr = _sampleRate;
    final samples = <double>[];

    void addDualTone(double f1, double f2, double durSec, {double vol = 0.85}) {
      final n = (sr * durSec).round();
      final fadeN = (sr * 0.02).round();
      for (var i = 0; i < n; i++) {
        final t = i / sr;
        var amp = vol;
        if (i < fadeN) {
          amp *= i / fadeN;
        } else if (i > n - fadeN) {
          amp *= (n - i) / fadeN;
        }
        final s = 0.5 * math.sin(2 * math.pi * f1 * t) +
            0.5 * math.sin(2 * math.pi * f2 * t);
        samples.add(amp * s);
      }
    }

    void addSilence(double durSec) {
      samples.addAll(List.filled((sr * durSec).round(), 0.0));
    }

    // Standard European/WhatsApp ringback cadence:
    // Beep (400ms) - silence (200ms) - Beep (400ms) - silence (2000ms)
    addDualTone(440, 480, 0.40);
    addSilence(0.20);
    addDualTone(440, 480, 0.40);
    addSilence(2.0);

    final pcm = ByteData(samples.length * 2);
    for (var i = 0; i < samples.length; i++) {
      final clamped = samples[i].clamp(-1.0, 1.0);
      pcm.setInt16(i * 2, (clamped * 32767).round(), Endian.little);
    }

    return _wrapWav(pcm.buffer.asUint8List(), sr);
  }

  /// Synthesizes an energetic, pleasant musical ringtone (melodic chime
  /// with harmonics, ~3s loop) for incoming call alerts.
  static Uint8List _buildRingtoneWav() {
    const sr = _sampleRate;
    final samples = <double>[];

    void addMelodyNote(double freqHz, double durSec, {double vol = 0.8}) {
      final n = (sr * durSec).round();
      final attackN = (sr * 0.01).round();
      final decayN = (sr * (durSec - 0.01)).round();
      for (var i = 0; i < n; i++) {
        final t = i / sr;
        var env = vol;
        if (i < attackN) {
          env *= (i / attackN);
        } else {
          env *= (1.0 - ((i - attackN) / decayN) * 0.6);
        }
        // Fundamental + overtone for a pleasant marimba/chime tone
        final s = 0.7 * math.sin(2 * math.pi * freqHz * t) +
            0.3 * math.sin(2 * math.pi * freqHz * 2 * t);
        samples.add(env * s);
      }
    }

    void addSilence(double durSec) {
      samples.addAll(List.filled((sr * durSec).round(), 0.0));
    }

    // Melodic sequence: E5, G#5, B5, E6, B5, E6
    addMelodyNote(659.25, 0.12);
    addSilence(0.04);
    addMelodyNote(830.61, 0.12);
    addSilence(0.04);
    addMelodyNote(987.77, 0.12);
    addSilence(0.04);
    addMelodyNote(1318.51, 0.28);
    addSilence(0.12);
    addMelodyNote(987.77, 0.14);
    addSilence(0.04);
    addMelodyNote(1318.51, 0.38);
    addSilence(1.8);

    final pcm = ByteData(samples.length * 2);
    for (var i = 0; i < samples.length; i++) {
      final clamped = samples[i].clamp(-1.0, 1.0);
      pcm.setInt16(i * 2, (clamped * 32767).round(), Endian.little);
    }

    return _wrapWav(pcm.buffer.asUint8List(), sr);
  }

  static Uint8List _wrapWav(Uint8List pcmBytes, int sampleRate) {
    const channels = 1;
    const bitsPerSample = 16;
    final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    const blockAlign = channels * bitsPerSample ~/ 8;
    final dataSize = pcmBytes.length;

    final header = BytesBuilder();
    void writeString(String s) => header.add(s.codeUnits);
    void writeUint32(int v) => header.add([
          v & 0xff,
          (v >> 8) & 0xff,
          (v >> 16) & 0xff,
          (v >> 24) & 0xff,
        ]);
    void writeUint16(int v) => header.add([v & 0xff, (v >> 8) & 0xff]);

    writeString('RIFF');
    writeUint32(36 + dataSize);
    writeString('WAVE');
    writeString('fmt ');
    writeUint32(16);
    writeUint16(1); // PCM
    writeUint16(channels);
    writeUint32(sampleRate);
    writeUint32(byteRate);
    writeUint16(blockAlign);
    writeUint16(bitsPerSample);
    writeString('data');
    writeUint32(dataSize);

    final builder = BytesBuilder()
      ..add(header.toBytes())
      ..add(pcmBytes);
    return builder.toBytes();
  }
}
