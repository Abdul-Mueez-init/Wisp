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

  static void _assertInitialized() {
    if (!_initialized) {
      throw StateError(
        'WebrtcConfig.initialize() must be called before use (see main.dart).',
      );
    }
  }

  /// Raw ICE server list, in the shape `flutter_webrtc`'s
  /// `RTCConfiguration`/`RTCPeerConnection.new` expects under the
  /// `iceServers` key.
  static List<Map<String, dynamic>> get iceServers {
    _assertInitialized();
    final servers = <Map<String, dynamic>>[_publicStunServer];
    if (_turnUrl.isNotEmpty) {
      servers.add({
        'urls': _turnUrl,
        if (_turnUsername.isNotEmpty) 'username': _turnUsername,
        if (_turnCredential.isNotEmpty) 'credential': _turnCredential,
      });
    }
    return servers;
  }

  /// True once real TURN credentials are filled in — used only to
  /// surface an honest "STUN-only, may not traverse strict NATs"
  /// note in the UI if you want one; not required for calls to work.
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
