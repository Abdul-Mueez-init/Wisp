// lib/features/location/widgets/location_bubble_content.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../../core/theme/app_theme.dart';
import '../../../models/message.dart';
import '../providers/location_provider.dart';
import '../screens/location_viewer_screen.dart';

/// Batch 5e-i/5e-ii — renders both 'location_current' (single pin,
/// address label) and 'location_live' (continuously-updated pin,
/// "Sharing live location" / "Live location ended" status row instead
/// of an address — matches design.md's `location_sharing` mock for the
/// active case). Stateful purely so expiry can flip the status label
/// without waiting for a new realtime event on the row — client-side
/// expiry only, same reasoning as `typing_status`'s staleness filter.
class LocationBubbleContent extends ConsumerStatefulWidget {
  const LocationBubbleContent(
      {super.key, required this.message, required this.isMine});

  final Message message;
  final bool isMine;

  @override
  ConsumerState<LocationBubbleContent> createState() =>
      _LocationBubbleContentState();
}

class _LocationBubbleContentState extends ConsumerState<LocationBubbleContent> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Only live messages need a periodic rebuild to notice their own
    // expiry — a 'location_current' pin never changes state.
    if (widget.message.isLiveLocation) {
      _tick = Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final isMine = widget.isMine;
    final lat = message.locationLat;
    final lng = message.locationLng;
    final textColor = isMine ? AppColors.cream : AppColors.onSurface;

    if (lat == null || lng == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.paddingBubbleX,
          vertical: AppSpacing.paddingBubbleY,
        ),
        child: Text(
          'Location unavailable',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: textColor),
        ),
      );
    }

    final point = ll.LatLng(lat, lng);
    final isLive = message.isLiveLocation;
    final expiresAt = message.liveLocationExpiresAt;
    final expired =
        isLive && expiresAt != null && DateTime.now().isAfter(expiresAt);

    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
            builder: (_) => LocationViewerScreen(lat: lat, lng: lng)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 140,
            width: double.infinity,
            child: IgnorePointer(
              child: Opacity(
                opacity: expired ? 0.6 : 1.0,
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: point,
                    initialZoom: 15,
                    interactionOptions:
                        const InteractionOptions(flags: InteractiveFlag.none),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.wisp.app',
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: point,
                          width: 32,
                          height: 32,
                          child: Icon(
                            Icons.location_on,
                            color:
                                expired ? AppColors.outline : AppColors.primary,
                            size: 32,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.paddingBubbleX,
              8,
              AppSpacing.paddingBubbleX,
              AppSpacing.paddingBubbleY,
            ),
            child: isLive
                ? _LiveStatusRow(expired: expired, textColor: textColor)
                : _AddressLabel(lat: lat, lng: lng, textColor: textColor),
          ),
        ],
      ),
    );
  }
}

class _AddressLabel extends ConsumerWidget {
  const _AddressLabel(
      {required this.lat, required this.lng, required this.textColor});

  final double lat;
  final double lng;
  final Color textColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final addressAsync = ref.watch(reverseGeocodeProvider((lat, lng)));
    return addressAsync.when(
      data: (address) => Text(
        address,
        style:
            Theme.of(context).textTheme.bodyLarge?.copyWith(color: textColor),
      ),
      loading: () => SizedBox(
        height: 16,
        width: 120,
        child: LinearProgressIndicator(
          color: AppColors.primary.withValues(alpha: 0.5),
          backgroundColor: Colors.transparent,
        ),
      ),
      error: (_, __) => Text(
        '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
        style:
            Theme.of(context).textTheme.bodyLarge?.copyWith(color: textColor),
      ),
    );
  }
}

/// design.md-style status row: a small dot (Moderate Green while
/// active, muted Laurel Green once ended) + label. "Sharing live
/// location" matches the Stitch mock's exact wording.
class _LiveStatusRow extends StatelessWidget {
  const _LiveStatusRow({required this.expired, required this.textColor});

  final bool expired;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final dotColor = expired ? AppColors.outline : AppColors.primary;
    final label = expired ? 'Live location ended' : 'Sharing live location';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context)
              .textTheme
              .labelMedium
              ?.copyWith(color: expired ? AppColors.outline : textColor),
        ),
      ],
    );
  }
}
