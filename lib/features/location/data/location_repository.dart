// lib/features/location/data/location_repository.dart
import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../../../core/errors/failure.dart';

/// Current + (Batch 5e-ii) live device location, plus reverse
/// geocoding via Nominatim — OpenStreetMap's free reverse-geocoding
/// service, per the handoff doc's decision #1. No paid geocoding API,
/// same zero-cost-stack reasoning already applied to flutter_map/OSM
/// tiles for rendering.
class LocationRepository {
  LocationRepository(this._httpClient);
  final http.Client _httpClient;

  /// Nominatim's usage policy caps free requests at ~1/sec and requires
  /// a descriptive User-Agent. This is a demo-scale identifier, not a
  /// production contact address — same honesty pattern as the
  /// TURN-server disclosure in PRD.md section 11.
  static const _userAgent = 'WispApp-Portfolio-Demo/0.1';
  static const _minRequestGap = Duration(milliseconds: 1100);
  DateTime? _lastRequestAt;

  /// In-memory cache keyed by rounded "lat,lng" so the same pin isn't
  /// re-geocoded twice in a session (handoff doc decision #1).
  final Map<String, String> _addressCache = {};

  /// Resolves the current device position, requesting permission if
  /// needed. Throws [LocationFailure] with a user-facing message on
  /// denial/disabled-service rather than letting a raw geolocator
  /// exception reach the UI.
  Future<Position> getCurrentPosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const LocationFailure(
        'Location services are turned off. Enable them to share your location.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw const LocationFailure('Location permission denied.');
      }
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationFailure(
        'Location permission permanently denied. Enable it in system settings.',
      );
    }

    try {
      return await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
    } catch (e) {
      throw LocationFailure('Could not get current location: $e');
    }
  }

  /// Foreground-only, distance-filtered position stream — built now so
  /// Batch 5e-ii's live-location controller doesn't need a second
  /// repository method added later. Per handoff doc decision #3, not
  /// wired to anything yet (no background-location setup, deliberate
  /// scope call).
  Stream<Position> watchPosition() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 15,
      ),
    );
  }

  /// Reverse-geocodes [lat]/[lng] to a short address, e.g.
  /// "123 Design St, San Francisco". Falls back to a plain "lat, lng"
  /// string on any failure/timeout — must never block sending a
  /// location message (handoff doc decision #1).
  Future<String> reverseGeocode(double lat, double lng) async {
    final cacheKey = '${lat.toStringAsFixed(5)},${lng.toStringAsFixed(5)}';
    final cached = _addressCache[cacheKey];
    if (cached != null) return cached;

    final fallback = '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';

    try {
      await _throttle();
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?format=jsonv2&lat=$lat&lon=$lng&addressdetails=0&zoom=18',
      );
      final response = await _httpClient.get(uri, headers: {
        'User-Agent': _userAgent
      }).timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) return fallback;

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final displayName = body['display_name'] as String?;
      if (displayName == null || displayName.isEmpty) return fallback;

      // display_name is a long comma chain (street, suburb, city,
      // county, postcode, country...) — keep the first two segments to
      // match design.md's short "123 Design St, San Francisco" style.
      final parts = displayName.split(',').map((p) => p.trim()).toList();
      final short = parts.take(2).join(', ');
      _addressCache[cacheKey] = short;
      return short;
    } catch (_) {
      return fallback;
    }
  }

  Future<void> _throttle() async {
    final last = _lastRequestAt;
    if (last != null) {
      final elapsed = DateTime.now().difference(last);
      if (elapsed < _minRequestGap) {
        await Future.delayed(_minRequestGap - elapsed);
      }
    }
    _lastRequestAt = DateTime.now();
  }
}
