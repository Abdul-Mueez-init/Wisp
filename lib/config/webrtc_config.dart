import 'package:audio_session/audio_session.dart';

/// Shared WebRTC config per architecture.md's "one shared config class,
/// nothing calls the SDK directly" shape (same pattern as `AiConfig` /
/// `SupabaseConfig`). Feature code (features/calls/) reads
/// [WebrtcConfig.iceServers] / [WebrtcConfig.rtcConfiguration] only —
/// never builds its own ICE server list.
///
/// Phase 10 decision #1 (confirmed): `.env` carries TURN credentials the
/// same way Gemini/Groq/Supabase keys already do. A public Google STUN
/// server is always included as a baseline — TURN entries are added on
/// top only if `TURN_URL` is non-empty, so the app still works
/// (STUN-only, weaker NAT traversal) before real TURN credentials are
/// filled in, per your "set up the keys, I'll fill in values after"
/// call. PRD.md §11's honest-limitation note applies once real TURN
/// creds are in: fine for demo/testing, not stress-tested for volume.
class WebrtcConfig {
  WebrtcConfig._();

  static bool _initialized = false;
  static late final String _turnUrl;
  static late final String _turnUsername;
  static late final String _turnCredential;

  static const _publicStunServer = {
    'urls': 'stun:stun.l.google.com:19302',
  };

  static void initialize({
    required String turnUrl,
    required String turnUsername,
    required String turnCredential,
  }) {
    _turnUrl = turnUrl.trim();
    _turnUsername = turnUsername.trim();
    _turnCredential = turnCredential.trim();
    _initialized = true;
  }

  /// Bugfix (reported: "can't hear the beep sound mid call"): configures
  /// the app's single shared `AudioSession` once, at startup, to a
  /// `playAndRecord`/voice-chat category compatible with both an active
  /// WebRTC call AND the `just_audio`-based ring/dial tone
  /// (`CallSoundPlayer`) — without this, the two negotiate for audio
  /// focus independently and the platform silences/ducks whichever one
  /// asked second (see `CallSoundPlayer`'s doc comment for the
  /// Android-specific half of this fix). Safe/cheap to call once at app
  /// boot even on sessions that never place a call.
  static Future<void> configureAudioSession() async {
    final session = await AudioSession.instance;
    // Bugfix: this whole object used to be `const AudioSessionConfiguration(...)`.
    // `AVAudioSessionCategoryOptions` overloads `|` as a normal *instance*
    // method (see audio_session's darwin.dart), and Dart's constant
    // evaluator only folds `|`/`&`/etc. for the built-in numeric/bool/
    // String types — it can't evaluate a user-defined operator overload
    // at compile time. `allowBluetooth | defaultToSpeaker | mixWithOthers`
    // is therefore not a valid *constant* expression, which is exactly
    // what the analyzer/compiler was rejecting on these two lines.
    // Dropping `const` here (the constructor itself stays `const`-capable
    // for callers who don't need this combined-flags case) makes the `|`
    // calls happen at ordinary runtime instead, which is perfectly legal
    // Dart — this object is only ever built once at app boot anyway, so
    // there's no performance reason to insist on `const`.
    await session.configure(AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
      avAudioSessionCategoryOptions:
          AVAudioSessionCategoryOptions.allowBluetooth |
              AVAudioSessionCategoryOptions.defaultToSpeaker |
              AVAudioSessionCategoryOptions.mixWithOthers,
      avAudioSessionMode: AVAudioSessionMode.voiceChat,
      avAudioSessionRouteSharingPolicy:
          AVAudioSessionRouteSharingPolicy.defaultPolicy,
      avAudioSessionSetActiveOptions:
          AVAudioSessionSetActiveOptions.notifyOthersOnDeactivation,
      androidAudioAttributes: const AndroidAudioAttributes(
        contentType: AndroidAudioContentType.speech,
        usage: AndroidAudioUsage.voiceCommunication,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      androidWillPauseWhenDucked: false,
    ));
  }

  static void _assertInitialized() {
    if (!_initialized) {
      throw StateError(
        'WebrtcConfig.initialize() must be called before use (see main.dart).',
      );
    }
  }

  /// Raw ICE server list, in the shape `flutter_webrtc`'s
  /// `RTCConfiguration`/`RTCPeerConnection.new` expects under the
  /// `iceServers` key. Supports comma-separated UDP and TCP/TLS TURN URLs.
  static List<Map<String, dynamic>> get iceServers {
    _assertInitialized();
    final servers = <Map<String, dynamic>>[_publicStunServer];
    if (_turnUrl.isNotEmpty) {
      final urls = _turnUrl
          .split(',')
          .map((u) => u.trim())
          .where((u) => u.isNotEmpty)
          .toList();
      if (urls.isNotEmpty) {
        servers.add({
          'urls': urls.length == 1 ? urls.first : urls,
          if (_turnUsername.isNotEmpty) 'username': _turnUsername,
          if (_turnCredential.isNotEmpty) 'credential': _turnCredential,
        });
      }
    }
    return servers;
  }

  /// True once real TURN credentials are filled in — used only to
  /// surface an honest "STUN-only, may not traverse strict NATs" note
  /// in the UI if you want one; not required for calls to work.
  static bool get hasTurnConfigured {
    _assertInitialized();
    return _turnUrl.isNotEmpty;
  }

  /// Ready-to-pass config map for `RTCPeerConnection.createPeerConnection`.
  static Map<String, dynamic> get rtcConfiguration => {
        'iceServers': iceServers,
        'sdpSemantics': 'unified-plan',
      };
}
