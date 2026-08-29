// lib/features/calls/data/webrtc_session.dart
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../config/webrtc_config.dart';

/// Wraps one `RTCPeerConnection` + its local/remote media for a single
/// active call. A fresh instance is created per call by CallController
/// and disposed at the end of that call — never reused. Mirrors
/// AiConfig's "shared wrapper, nothing outside touches the SDK
/// directly" discipline, just applied to `flutter_webrtc` instead of
/// Gemini/Groq.
class WebrtcSession {
  RTCPeerConnection? _pc;
  MediaStream? localStream;
  MediaStream? remoteStream;

  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  bool _isMuted = false;
  bool _isCameraOff = false;
  bool get isMuted => _isMuted;
  bool get isCameraOff => _isCameraOff;

  final List<RTCIceCandidate> _pendingRemoteCandidates = [];
  bool _remoteDescriptionSet = false;

  void Function(RTCIceCandidate candidate)? onLocalIceCandidate;
  void Function(RTCPeerConnectionState state)? onConnectionStateChanged;

  /// Requests mic (+ camera if [isVideo]), opens the peer connection,
  /// and wires local track/candidate callbacks. Must be called before
  /// createOffer/createAnswer.
  Future<void> init({required bool isVideo}) async {
    await localRenderer.initialize();
    await remoteRenderer.initialize();

    localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': isVideo ? {'facingMode': 'user'} : false,
    });
    localRenderer.srcObject = localStream;

    _pc = await createPeerConnection(WebrtcConfig.rtcConfiguration);

    for (final track in localStream!.getTracks()) {
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
    final desc = RTCSessionDescription(
      payload['sdp'] as String,
      payload['type'] as String,
    );
    await _pc!.setRemoteDescription(desc);
    _remoteDescriptionSet = true;
    for (final candidate in _pendingRemoteCandidates) {
      await _pc!.addCandidate(candidate);
    }
    _pendingRemoteCandidates.clear();
  }

  Future<void> addRemoteIceCandidate(Map<String, dynamic> payload) async {
    final candidate = RTCIceCandidate(
      payload['candidate'] as String?,
      payload['sdpMid'] as String?,
      payload['sdpMLineIndex'] as int?,
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

  Future<void> dispose() async {
    await localRenderer.dispose();
    await remoteRenderer.dispose();
    for (final t in localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      await t.stop();
    }
    await localStream?.dispose();
    await remoteStream?.dispose();
    await _pc?.close();
    await _pc?.dispose();
  }
}
