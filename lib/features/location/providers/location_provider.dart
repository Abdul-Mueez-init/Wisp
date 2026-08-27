// lib/features/location/providers/location_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../auth/providers/auth_provider.dart';
import '../../chat/providers/message_provider.dart';
import '../data/location_repository.dart';

final locationRepositoryProvider = Provider<LocationRepository>((ref) {
  return LocationRepository(http.Client());
});

/// Resolves + caches a short address label for a pinned coordinate —
/// Riverpod's own provider caching gives the per-session dedupe the
/// handoff doc's decision #1 calls for, on top of the repository's own
/// in-memory cache.
final reverseGeocodeProvider =
    FutureProvider.family<String, (double, double)>((ref, coords) {
  final (lat, lng) = coords;
  return ref.read(locationRepositoryProvider).reverseGeocode(lat, lng);
});

/// Batch 5e-i — sends a one-off current-location message. A plain
/// [AsyncNotifier] rather than folding into `SendMessageController`,
/// since it also owns the device-location fetch, not just the insert.
class SendLocationController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<bool> sendCurrentLocation({required String conversationId}) async {
    final myId = ref.read(currentSessionProvider)?.user.id;
    if (myId == null) return false;

    state = const AsyncLoading();
    final result = await AsyncValue.guard(() async {
      final position =
          await ref.read(locationRepositoryProvider).getCurrentPosition();
      await ref.read(messageRepositoryProvider).sendLocationMessage(
            conversationId: conversationId,
            senderId: myId,
            lat: position.latitude,
            lng: position.longitude,
          );
    });
    state = result;
    return !result.hasError;
  }
}

final sendLocationControllerProvider =
    AsyncNotifierProvider<SendLocationController, void>(
  SendLocationController.new,
);
