// lib/features/location/screens/location_viewer_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';

/// Batch 5e-i — fullscreen, interactive view of a shared pin. Reuses
/// the bubble's flutter_map/OSM stack; adds an "open in Maps" action
/// for turn-by-turn navigation, since flutter_map itself has no
/// routing.
class LocationViewerScreen extends StatelessWidget {
  const LocationViewerScreen({super.key, required this.lat, required this.lng});

  final double lat;
  final double lng;

  @override
  Widget build(BuildContext context) {
    final point = ll.LatLng(lat, lng);
    return Scaffold(
      backgroundColor: AppColors.backgroundBase,
      appBar: AppBar(
        title: const Text('Shared location'),
        actions: [
          IconButton(
            icon: const Icon(Icons.directions_outlined),
            tooltip: 'Open in Maps',
            onPressed: () => _openInMaps(context),
          ),
        ],
      ),
      body: FlutterMap(
        options: MapOptions(initialCenter: point, initialZoom: 16),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.wisp.app',
          ),
          MarkerLayer(
            markers: [
              Marker(
                point: point,
                width: 40,
                height: 40,
                child: const Icon(
                  Icons.location_on,
                  color: AppColors.primary,
                  size: 40,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openInMaps(BuildContext context) async {
    final geoUri = Uri.parse('geo:$lat,$lng?q=$lat,$lng');
    final ok = await launchUrl(geoUri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      final webUri = Uri.parse(
        'https://www.openstreetmap.org/?mlat=$lat&mlon=$lng#map=16/$lat/$lng',
      );
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
    }
  }
}
