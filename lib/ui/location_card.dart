import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../messaging/store.dart';
import 'theme.dart';

/// Map tiles come from the network; widget tests have none, so they show the
/// pin on a plain background instead.
final bool mapTilesEnabled = !Platform.environment.containsKey('FLUTTER_TEST');

/// "± 8 m" for an accuracy radius, or null when unknown.
String? accuracyLabel(double? metres) {
  if (metres == null || !metres.isFinite || metres < 0) {
    return null;
  }
  if (metres >= 1000) {
    return '± ${(metres / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';
  }
  return '± ${metres.round()} m';
}

/// Google Maps directions to a position; opens the app when installed.
Uri directionsUri(double lat, double lon) => Uri.https(
  'www.google.com',
  '/maps/dir/',
  {'api': '1', 'destination': '$lat,$lon'},
);

/// Where an SOS was sent from: the street address in large type, how sure
/// the position is, a small map with the pin, and buttons to get directions
/// or copy the place.
class LocationCard extends StatelessWidget {
  final StoredMessage m;

  /// Shows the map preview; off in dense lists.
  final bool map;
  const LocationCard(this.m, {super.key, this.map = true});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final lat = m.latitude!, lon = m.longitude!;
    final coords = '${lat.toStringAsFixed(6)}, ${lon.toStringAsFixed(6)}';
    final address = m.placeName;
    final accuracy = accuracyLabel(m.accuracy);
    final source = m.address != null
        ? 'Địa chỉ do máy người gửi xác định'
        : address != null
        ? 'Người gửi không có mạng; địa chỉ do máy này tra'
        : 'Chưa có địa chỉ: sẽ tự tra khi có Internet';
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (map) SizedBox(height: 132, child: _MapPreview(m)),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(Icons.place_rounded, color: p.danger, size: 20),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(
                        address ?? coords,
                        key: const ValueKey('sos-address'),
                        style: const TextStyle(
                          fontSize: 14.5,
                          height: 1.35,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        [if (address != null) coords, ?accuracy].join('  •  '),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: p.muted,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        source,
                        style: TextStyle(fontSize: 11.5, color: p.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 4),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: () => openDirections(context, lat, lon),
                  icon: const Icon(Icons.directions_rounded, size: 18),
                  label: const Text('Chỉ đường'),
                ),
                TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(
                        text: address == null ? coords : '$address ($coords)',
                      ),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Đã sao chép vị trí')),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy_rounded, size: 17),
                  label: const Text('Sao chép'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Future<void> openDirections(
    BuildContext context,
    double lat,
    double lon,
  ) async {
    var opened = false;
    try {
      opened = await launchUrl(
        directionsUri(lat, lon),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      opened = false;
    }
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Không mở được bản đồ. Đã có tọa độ để sao chép.'),
        ),
      );
    }
  }
}

class _MapPreview extends StatelessWidget {
  final StoredMessage m;
  const _MapPreview(this.m);
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final point = LatLng(m.latitude!, m.longitude!);
    final radius = m.accuracy;
    final pin = Icon(
      Icons.location_on,
      color: p.danger,
      size: 38,
      shadows: const [Shadow(blurRadius: 6, color: Colors.black38)],
    );
    if (!mapTilesEnabled) {
      return ColoredBox(
        color: p.accentSoft,
        child: Center(child: pin),
      );
    }
    return Semantics(
      label: 'Bản đồ vị trí người gửi',
      child: FlutterMap(
        options: MapOptions(
          initialCenter: point,
          initialZoom: 17,
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.none,
          ),
          backgroundColor: p.accentSoft,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'vn.emergency.ble_emergency_app',
          ),
          if (radius != null && radius > 0 && radius < 5000)
            CircleLayer(
              circles: [
                CircleMarker(
                  point: point,
                  radius: radius,
                  useRadiusInMeter: true,
                  color: p.danger.withValues(alpha: .15),
                  borderColor: p.danger.withValues(alpha: .5),
                  borderStrokeWidth: 1.5,
                ),
              ],
            ),
          MarkerLayer(
            markers: [
              Marker(
                point: point,
                width: 40,
                height: 40,
                alignment: Alignment.topCenter,
                child: pin,
              ),
            ],
          ),
          const SimpleAttributionWidget(
            source: Text('OpenStreetMap', style: TextStyle(fontSize: 10)),
          ),
        ],
      ),
    );
  }
}
