// lib/features/calls/data/webrtc_session.dart
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../config/webrtc_config.dart';

/// Wraps one `RTCPeerConnection` + its local/remote media for a single
/// active call. A fresh instance is created per call by CallController
/// and disposed at the end of that call — never reused. Mirrors
/// AiConfig's "shared wrapper, nothing outside touches the SDK
/// directly" discipline, just applied to `flutter_webrtc` instead of
/// Gemini/Groq.
///
/// Bugfix/feature session: `init()` used to do local-media grab AND
/// peer-connection setup in one shot. Split into [initLocalMedia] +
/// [initPeerConnection] (still both callable via [init] for the caller
/// side, unchanged) so the callee can grab the camera/mic — and show a
/// live preview — the instant an incoming video call rings, before they
/// even tap Accept, matching WhatsApp. `init()` remains for the caller
/// side, which already wants both steps back-to-back.
class WebrtcSession {
  RTCPeerConnection? _pc;
  MediaStream? localStream;
  MediaStream? remoteStream;

  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  bool _isMuted = false;
  bool _isCameraOff = false;
  bool _isSpeakerOn = false;
  bool _localRendererInitialized = false;
  bool _remoteRendererInitialized = false;

  bool get isMuted => _isMuted;
  bool get isCameraOff => _isCameraOff;
  bool get isSpeakerOn => _isSpeakerOn;

  /// True once [initLocalMedia] has grabbed the mic/camera — lets
  /// CallController tell "already have a preview session running" apart
  /// from "need to start from scratch".
  bool get hasLocalMedia => localStream != null;
  bool get hasPeerConnection => _pc != null;

  final List<RTCIceCandidate> _pendingRemoteCandidates = [];
  bool _remoteDescriptionSet = false;

  void Function(RTCIceCandidate candidate)? onLocalIceCandidate;
  void Function(RTCPeerConnectionState state)? onConnectionStateChanged;

  /// Step 1 of 2: grabs the mic (+ camera if [isVideo]) and starts the
  /// local preview renderer — no peer connection yet. Safe to call more
  /// than once; a second call is a no-op if media was already grabbed,
  /// so CallController doesn't need to track that itself.
  Future<void> initLocalMedia({required bool isVideo}) async {
    if (localStream != null) return;
    if (!_localRendererInitialized) {
      await localRenderer.initialize();
      _localRendererInitialized = true;
    }

    localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': isVideo ? {'facingMode': 'user'} : false,
    });
    localRenderer.srcObject = localStream;

    // WhatsApp-style default: video calls start on speakerphone (you're
    // holding the phone away from your ear to look at the screen);
    // audio calls start on the earpiece like an ordinary phone call.
    await setSpeaker(isVideo);
  }

  /// Step 2 of 2: opens the actual `RTCPeerConnection` and attaches
  /// whatever local tracks [initLocalMedia] already grabbed. Safe to
  /// call even if a peer connection already exists (no-op).
  Future<void> initPeerConnection() async {
    if (_pc != null) return;
    if (!_remoteRendererInitialized) {
      await remoteRenderer.initialize();
      _remoteRendererInitialized = true;
    }

    _pc = await createPeerConnection(WebrtcConfig.rtcConfiguration);

    for (final track
        in localStream?.getTracks() ?? const <MediaStreamTrack>[]) {
      await _pc!.addTrack(track, localStream!);
    }

    _pc!.onIceCandidate = (candidate) {
      if (candidate.candidate == null) return;
      onLocalIceCandidate?.call(candidate);
    };

    _pc!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        remoteStream = event.streams[0];
        remoteRenderer.srcObject = remoteStream;
      }
    };

    _pc!.onConnectionState = (state) => onConnectionStateChanged?.call(state);
  }

  /// Convenience for the caller side: grabs local media and opens the
  /// peer connection back-to-back. Unchanged call sites keep working
  /// exactly as before.
  Future<void> init({required bool isVideo}) async {
    await initLocalMedia(isVideo: isVideo);
    await initPeerConnection();
  }

  Future<Map<String, dynamic>> createOffer() async {
    final desc = await _pc!.createOffer();
    await _pc!.setLocalDescription(desc);
    return {'sdp': desc.sdp, 'type': desc.type};
  }

  /// Sets the caller's offer as our remote description, then answers.
  Future<Map<String, dynamic>> createAnswer(
    Map<String, dynamic> remoteOffer,
  ) async {
    await setRemoteDescription(remoteOffer);
    final desc = await _pc!.createAnswer();
    await _pc!.setLocalDescription(desc);
    return {'sdp': desc.sdp, 'type': desc.type};
  }

  /// Sets the peer's SDP (offer on the callee side, answer on the
  /// caller side) and flushes any ICE candidates that arrived before
  /// it — candidates can race ahead of the SDP over a broadcast
  /// channel with no ordering guarantee between event types.
  Future<void> setRemoteDescription(Map<String, dynamic> payload) async {
    final data = payload['payload'] is Map
        ? Map<String, dynamic>.from(payload['payload'] as Map)
        : payload;
    final sdp = data['sdp'] as String?;
    var type = data['type'] as String?;
    if (type == 'broadcast' || type == null) {
      // If the outer envelope leaked through or type wasn't provided,
      // deduce from the current signaling state: if we already sent a local offer,
      // the remote description is an answer; otherwise it's an offer.
      type = (_pc?.signalingState ==
              RTCSignalingState.RTCSignalingStateHaveLocalOffer)
          ? 'answer'
          : 'offer';
    }
    if (sdp == null) {
      throw ArgumentError('Invalid SDP payload received: $payload');
    }
    final desc = RTCSessionDescription(sdp, type);
    await _pc!.setRemoteDescription(desc);
    _remoteDescriptionSet = true;
    for (final candidate in _pendingRemoteCandidates) {
      await _pc!.addCandidate(candidate);
    }
    _pendingRemoteCandidates.clear();
  }

  Future<void> addRemoteIceCandidate(Map<String, dynamic> payload) async {
    final data = payload['payload'] is Map
        ? Map<String, dynamic>.from(payload['payload'] as Map)
        : payload;
    final candidateStr = data['candidate'] as String?;
    if (candidateStr == null || candidateStr.isEmpty) return;
    final candidate = RTCIceCandidate(
      candidateStr,
      data['sdpMid'] as String?,
      data['sdpMLineIndex'] as int?,
    );
    if (_remoteDescriptionSet) {
      await _pc!.addCandidate(candidate);
    } else {
      _pendingRemoteCandidates.add(candidate);
    }
  }

  static Map<String, dynamic> candidateToJson(RTCIceCandidate c) => {
        'candidate': c.candidate,
        'sdpMid': c.sdpMid,
        'sdpMLineIndex': c.sdpMLineIndex,
      };

  void toggleMute() {
    _isMuted = !_isMuted;
    for (final t in localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = !_isMuted;
    }
  }

  void toggleCamera() {
    _isCameraOff = !_isCameraOff;
    for (final t in localStream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = !_isCameraOff;
    }
  }

  Future<void> switchCamera() async {
    final videoTracks = localStream?.getVideoTracks() ?? const [];
    if (videoTracks.isNotEmpty) {
      await Helper.switchCamera(videoTracks.first);
    }
  }

  /// Ear-speaker <-> phone-speaker toggle. Best-effort: some
  /// platforms/devices reject the switch, and an audio-routing toggle
  /// must never be allowed to fail the call itself.
  Future<void> setSpeaker(bool on) async {
    _isSpeakerOn = on;
    try {
      await Helper.setSpeakerphoneOn(on);
    } catch (_) {}
  }

  Future<void> toggleSpeaker() => setSpeaker(!_isSpeakerOn);

  Future<void> dispose() async {
    try {
      await localRenderer.dispose();
    } catch (_) {}
    try {
      await remoteRenderer.dispose();
    } catch (_) {}
    for (final t in localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      await t.stop();
    }
    await localStream?.dispose();
    await remoteStream?.dispose();
    await _pc?.close();
    await _pc?.dispose();
  }
}
