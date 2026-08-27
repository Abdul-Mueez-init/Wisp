// lib/features/location/providers/live_location_provider.dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';

import '../../auth/providers/auth_provider.dart';
import '../../chat/providers/message_provider.dart';
import 'location_provider.dart';

/// WhatsApp's own three options — PRD.md's "Core Principles" says
/// WhatsApp is the reference point, so matching these exactly per the
/// handoff doc's decision #2 rather than inventing new durations.
enum LiveLocationDuration {
  fifteenMinutes(Duration(minutes: 15), '15 minutes'),
  oneHour(Duration(hours: 1), '1 hour'),
  eightHours(Duration(hours: 8), '8 hours');

  const LiveLocationDuration(this.duration, this.label);
  final Duration duration;
  final String label;
}

/// Immutable snapshot of whether this device is currently sharing live
/// location, and where — used to render the "Sharing live location ·
/// Stop" banner and to guard against starting a second share while one
/// is already running.
class LiveLocationSharingState {
  const LiveLocationSharingState({
    this.isStarting = false,
    this.conversationId,
    this.messageId,
    this.expiresAt,
  });

  final bool isStarting;
  final String? conversationId;
  final String? messageId;
  final DateTime? expiresAt;

  bool get isActive => messageId != null;

  static const idle = LiveLocationSharingState();
}

/// Owns the whole live-location lifecycle: start → periodic position
/// stream → per-fix row updates → stop (on expiry, explicit "Stop
/// sharing", or leaving the chat screen). Same start/stop/auto-clear
/// shape as `TypingController` in Phase 4, foreground-only per handoff
/// doc decision #3 — no background-location setup, deliberate scope
/// call, not an oversight.
class LiveLocationController extends Notifier<LiveLocationSharingState> {
  StreamSubscription<Position>? _positionSub;
  Timer? _expiryTimer;

  @override
  LiveLocationSharingState build() {
    ref.onDispose(() {
      _positionSub?.cancel();
      _expiryTimer?.cancel();
    });
    return LiveLocationSharingState.idle;
  }

  Future<bool> start({
    required String conversationId,
    required LiveLocationDuration duration,
  }) async {
    final myId = ref.read(currentSessionProvider)?.user.id;
    if (myId == null) return false;

    // Only one active live share per device at a time — matches
    // WhatsApp's model and avoids two position streams writing to two
    // different message rows.
    await stop();

    state = const LiveLocationSharingState(isStarting: true);
    try {
      final position =
          await ref.read(locationRepositoryProvider).getCurrentPosition();
      final messageId = const Uuid().v4();
      final expiresAt = DateTime.now().add(duration.duration);

      await ref.read(messageRepositoryProvider).sendLiveLocationMessage(
            messageId: messageId,
            conversationId: conversationId,
            senderId: myId,
            lat: position.latitude,
            lng: position.longitude,
            expiresAt: expiresAt,
          );

      state = LiveLocationSharingState(
        conversationId: conversationId,
        messageId: messageId,
        expiresAt: expiresAt,
      );

      _positionSub = ref
          .read(locationRepositoryProvider)
          .watchPosition()
          .listen((position) => _onPosition(messageId, position),
              onError: (_) {});
      _expiryTimer = Timer(duration.duration, stop);
      return true;
    } catch (_) {
      state = LiveLocationSharingState.idle;
      return false;
    }
  }

  void _onPosition(String messageId, Position position) {
    // Fire-and-forget — a dropped pin update self-heals on the next
    // position fix, same reasoning as TypingController's writes.
    ref
        .read(messageRepositoryProvider)
        .updateLiveLocationPin(
          messageId: messageId,
          lat: position.latitude,
          lng: position.longitude,
        )
        .catchError((_) {});
  }

  /// Ends the active share, if any. Safe to call when nothing is
  /// active (no-ops).
  Future<void> stop() async {
    _positionSub?.cancel();
    _positionSub = null;
    _expiryTimer?.cancel();
    _expiryTimer = null;

    final messageId = state.messageId;
    if (messageId != null) {
      await ref
          .read(messageRepositoryProvider)
          .endLiveLocationEarly(messageId)
          .catchError((_) {});
    }
    state = LiveLocationSharingState.idle;
  }
}

final liveLocationControllerProvider =
    NotifierProvider<LiveLocationController, LiveLocationSharingState>(
  LiveLocationController.new,
);
