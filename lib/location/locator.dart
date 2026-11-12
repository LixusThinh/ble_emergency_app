import 'dart:io';

import 'package:flutter/services.dart';

import 'geocoder.dart';

/// A measured position.
class LocationFix {
  final double latitude, longitude;

  /// Metres the position is good to; null when the phone did not say.
  final double? accuracy;

  /// True for the phone's last known position rather than a fresh fix.
  final bool stale;
  const LocationFix(
    this.latitude,
    this.longitude, {
    this.accuracy,
    this.stale = false,
  });
}

/// Where this phone is.
abstract interface class Locator {
  /// Throws when there is no position (no permission, location off, no fix).
  Future<LocationFix> locate();
}

/// GPS and network positions from Android, see `MainActivity.locate`.
class PlatformLocator implements Locator {
  static const channel = MethodChannel('vn.emergency/ble');
  const PlatformLocator();
  @override
  Future<LocationFix> locate() async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('Lấy vị trí cần điện thoại Android');
    }
    final v = await channel.invokeMapMethod<String, dynamic>('location');
    final lat = (v?['latitude'] as num?)?.toDouble();
    final lon = (v?['longitude'] as num?)?.toDouble();
    if (lat == null || lon == null) {
      throw StateError('Không có vị trí');
    }
    return LocationFix(
      lat,
      lon,
      accuracy: (v?['accuracy'] as num?)?.toDouble(),
      stale: v?['stale'] == true,
    );
  }
}

/// Always the same place; the simulator's phones stand at HUTECH.
class FixedLocator implements Locator {
  final LocationFix fix;
  const FixedLocator(this.fix);
  static const hutech = FixedLocator(
    LocationFix(10.801603, 106.714778, accuracy: 8),
  );
  @override
  Future<LocationFix> locate() async => fix;
}

/// A position and, when the lookup worked, its street address.
typedef Place = ({LocationFix fix, String? address});

/// Locates, then looks the position up; the address is best effort.
Future<Place> locateAndName(Locator locator, Geocoder geocoder) async {
  final fix = await locator.locate();
  String? address;
  try {
    address = await geocoder.lookup(fix.latitude, fix.longitude);
  } catch (_) {
    address = null;
  }
  return (fix: fix, address: address);
}
