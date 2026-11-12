import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// Turns a position into a street address people can read. Every lookup
/// needs the Internet; callers treat null and errors alike as "no address".
abstract interface class Geocoder {
  Future<String?> lookup(double latitude, double longitude);
}

/// The phone's own geocoder (Google's on most Android phones), in Vietnamese
/// and without an API key.
class PlatformGeocoder implements Geocoder {
  static const channel = MethodChannel('vn.emergency/ble');
  const PlatformGeocoder();
  @override
  Future<String?> lookup(double latitude, double longitude) async {
    if (!Platform.isAndroid) {
      return null;
    }
    final v = await channel.invokeMethod<String>('geocode', {
      'latitude': latitude,
      'longitude': longitude,
    });
    return cleanAddress(v);
  }
}

/// OpenStreetMap's public Nominatim service, for phones without a platform
/// geocoder. Its policy asks for an identifying User-Agent and at most one
/// request a second, which [CachingGeocoder] keeps to.
class NominatimGeocoder implements Geocoder {
  final HttpClient Function() _client;
  NominatimGeocoder({HttpClient Function()? client})
    : _client = client ?? HttpClient.new;

  @override
  Future<String?> lookup(double latitude, double longitude) async {
    final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
      'format': 'jsonv2',
      'lat': '$latitude',
      'lon': '$longitude',
      'zoom': '18',
      'addressdetails': '1',
      'accept-language': 'vi',
    });
    final client = _client()..connectionTimeout = const Duration(seconds: 4);
    try {
      final request = await client.getUrl(uri);
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'SOSMesh/2.0 (emergency mesh app; course project)',
      );
      final response = await request.close();
      if (response.statusCode != 200) {
        await response.drain<void>();
        return null;
      }
      final body = await response.transform(utf8.decoder).join();
      return formatNominatim(jsonDecode(body));
    } finally {
      client.close(force: true);
    }
  }
}

/// Address from a Nominatim reverse result: house number and street first,
/// then ward, district and city, without postcode or country.
String? formatNominatim(Object? json) {
  if (json is! Map || json['error'] != null) {
    return null;
  }
  final a = json['address'];
  if (a is Map) {
    String? pick(List<String> keys) {
      for (final k in keys) {
        final v = a[k];
        if (v is String && v.trim().isNotEmpty) {
          return v.trim();
        }
      }
      return null;
    }

    final number = pick(['house_number']);
    final street = pick(['road', 'pedestrian', 'footway', 'path']);
    final place = pick(['amenity', 'building', 'shop', 'tourism', 'office']);
    final parts = [
      ?place,
      if (street != null) number == null ? street : '$number $street',
      ?pick(['quarter', 'neighbourhood', 'suburb', 'village', 'hamlet']),
      ?pick(['city_district', 'district', 'county', 'town']),
      ?pick(['city', 'state', 'province']),
    ];
    final unique = <String>[];
    for (final p in parts) {
      if (!unique.contains(p)) {
        unique.add(p);
      }
    }
    if (unique.length >= 2) {
      return cleanAddress(unique.join(', '));
    }
  }
  final name = json['display_name'];
  return name is String ? cleanAddress(_dropTail(name)) : null;
}

String _dropTail(String name) {
  final parts = name.split(',').map((s) => s.trim()).toList();
  // "…, Thành phố Hồ Chí Minh, 70000, Việt Nam": the last two say nothing.
  while (parts.isNotEmpty &&
      (RegExp(r'^\d{4,6}$').hasMatch(parts.last) ||
          parts.last == 'Việt Nam' ||
          parts.last == 'Vietnam')) {
    parts.removeLast();
  }
  return parts.join(', ');
}

/// Trims, collapses whitespace, drops a trailing country and caps the result
/// at what fits in a signed SOS (255 UTF-8 bytes). Null for nothing useful.
String? cleanAddress(String? raw) {
  if (raw == null) {
    return null;
  }
  var s = _dropTail(raw.replaceAll(RegExp(r'\s+'), ' ').trim());
  if (s.isEmpty) {
    return null;
  }
  while (utf8.encode(s).length > 255) {
    final cut = s.lastIndexOf(',');
    s = cut > 0 ? s.substring(0, cut) : s.substring(0, s.length - 1);
  }
  return s;
}

/// Tries each geocoder in turn, gives up after [timeout] overall, and
/// remembers answers by position rounded to about a metre, so a burst of SOS
/// from one place asks once. Lookups run one at a time and at most one a
/// second, as Nominatim's policy asks.
class CachingGeocoder implements Geocoder {
  final List<Geocoder> sources;
  final Duration timeout;
  final Duration spacing;
  final Map<String, String> _cache = {};
  Future<void> _last = Future.value();
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);
  CachingGeocoder(
    this.sources, {
    this.timeout = const Duration(seconds: 5),
    this.spacing = const Duration(seconds: 1),
  });

  /// The phone's geocoder, then OpenStreetMap.
  factory CachingGeocoder.standard() =>
      CachingGeocoder([const PlatformGeocoder(), NominatimGeocoder()]);

  static String _key(double lat, double lon) =>
      '${lat.toStringAsFixed(5)},${lon.toStringAsFixed(5)}';

  @override
  Future<String?> lookup(double latitude, double longitude) {
    final key = _key(latitude, longitude);
    final known = _cache[key];
    if (known != null) {
      return Future.value(known);
    }
    final run = _last.then((_) => _resolve(key, latitude, longitude));
    _last = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<String?> _resolve(String key, double lat, double lon) async {
    final known = _cache[key];
    if (known != null) {
      return known;
    }
    final wait = spacing - DateTime.now().difference(_lastAt);
    if (wait > Duration.zero) {
      await Future<void>.delayed(wait);
    }
    final deadline = DateTime.now().add(timeout);
    try {
      for (final g in sources) {
        final left = deadline.difference(DateTime.now());
        if (left <= Duration.zero) {
          break;
        }
        try {
          final v = await g.lookup(lat, lon).timeout(left);
          if (v != null) {
            return _cache[key] = v;
          }
        } catch (_) {
          // Offline, no service, or slow: try the next one.
        }
      }
      return null;
    } finally {
      _lastAt = DateTime.now();
    }
  }
}
