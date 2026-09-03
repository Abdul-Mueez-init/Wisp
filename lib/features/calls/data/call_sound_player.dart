// lib/features/calls/data/call_sound_player.dart
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';

/// The looping "beep… beep…" tone played from the moment a call starts
/// dialing/ringing until it's answered (or cancelled/declined/ends).
/// Generates its own short WAV in memory via a plain sine-wave synth —
/// deliberately not a bundled asset file: it means zero pubspec changes,
/// zero binary asset to ship, and the exact same tone on every platform.
/// One instance is owned by [CallController] and started/stopped purely
/// off `CallPhase` transitions — matches the "one small wrapper, nothing
/// else touches the underlying player directly" discipline used
/// elsewhere (AiConfig, WebrtcConfig).
class CallSoundPlayer {
  CallSoundPlayer() : _player = AudioPlayer();

  final AudioPlayer _player;
  bool _ready = false;
  bool _playing = false;

  static const _sampleRate = 44100;

  Future<void> _ensureReady() async {
    if (_ready) return;
    final bytes = _buildToneWav();
    await _player.setAudioSource(_InMemoryWavSource(bytes));
    await _player.setLoopMode(LoopMode.all);
    _ready = true;
  }

  /// Starts the looping tone if it isn't already playing. Safe to call
  /// repeatedly (CallController calls this on every phase change while
  /// still ringing/connecting) — a no-op if already playing.
  Future<void> start() async {
    if (_playing) return;
    try {
      await _ensureReady();
      _playing = true;
      await _player.seek(Duration.zero);
      await _player.play();
    } catch (_) {
      // Best-effort — a missing audio output device or plugin hiccup
      // must never block the actual call from proceeding.
      _playing = false;
    }
  }

  /// Stops and rewinds — called the instant a call becomes active, ends,
  /// or is declined/cancelled, so the tone never bleeds into a live
  /// call.
  Future<void> stop() async {
    if (!_playing) return;
    _playing = false;
    try {
      await _player.pause();
      await _player.seek(Duration.zero);
    } catch (_) {}
  }

  Future<void> dispose() async {
    _playing = false;
    try {
      await _player.dispose();
    } catch (_) {}
  }

  /// Synthesizes a soft double-beep cadence (~2.5s loop, 16-bit mono
  /// PCM wrapped in a minimal WAV header).
  static Uint8List _buildToneWav() {
    const sr = _sampleRate;
    final samples = <double>[];

    void addTone(double freqHz, double durSec, {double vol = 0.5}) {
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
        samples.add(amp * math.sin(2 * math.pi * freqHz * t));
      }
    }

    void addSilence(double durSec) {
      samples.addAll(List.filled((sr * durSec).round(), 0.0));
    }

    addTone(950, 0.18);
    addSilence(0.10);
    addTone(950, 0.18);
    addSilence(2.0);

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
    final blockAlign = channels * bitsPerSample ~/ 8;
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

/// Feeds the in-memory WAV bytes to just_audio without a bundled asset
/// file or a temp file on disk.
class _InMemoryWavSource extends StreamAudioSource {
  _InMemoryWavSource(this._bytes) : super(tag: 'call_ring_tone');
  final Uint8List _bytes;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    start ??= 0;
    end ??= _bytes.length;
    return StreamAudioResponse(
      sourceLength: _bytes.length,
      contentLength: end - start,
      offset: start,
      stream: Stream.value(_bytes.sublist(start, end)),
      contentType: 'audio/wav',
    );
  }
}
