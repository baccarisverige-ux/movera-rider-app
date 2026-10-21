import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';
import 'package:movera_rider/core/config/rider_zones.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Screens talk to this, never to Geolocator.
class LocationRepository {
  const LocationRepository({bool? isWeb}) : _isWeb = isWeb;

  final bool? _isWeb;

  /// Whether the browser's geolocation backs this repository.
  bool get isWeb => _isWeb ?? kIsWeb;

  /// Where the app keeps its own last good high-accuracy fix (Batch 10
  /// Phase 110). Coordinates only; used solely as a map-camera hint.
  static const lastGoodFixKey = 'movera.location.last_good_fix.v1';

  /// rider-r4-41: the zone id of the last good fix (a country, never a
  /// position). A device setting like the app language: the session wipe
  /// keeps it, so a cold start after sign-out still speaks the zone's
  /// default language instead of the home zone's.
  static const lastZoneKey = 'movera.location.last_zone.v1';

  Future<bool> isLocationServiceEnabled() {
    return Geolocator.isLocationServiceEnabled();
  }

  Future<LocationPermission> checkPermission() {
    return Geolocator.checkPermission();
  }

  /// rider-r4-21 / rider-r4-42: geolocator_web runs a bare
  /// getCurrentPosition() and answers deniedForever for *any* failure (the
  /// prompt dismissed, no position, a timeout). Only the Permissions API
  /// saying 'denied' is a real block, so the web answer is read again:
  /// 'prompt' is denied (ask again), 'granted' means the fix itself failed
  /// and the caller's position request reports it as unavailable.
  Future<LocationPermission> requestPermission() async {
    final requested = await Geolocator.requestPermission();
    if (!isWeb || requested != LocationPermission.deniedForever) {
      return requested;
    }
    try {
      return await Geolocator.checkPermission();
    } catch (_) {
      return requested;
    }
  }

  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) {
    return Geolocator.getCurrentPosition(
      locationSettings: locationSettings ??
          const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  /// The OS's cached last position (Android/iOS), typically near-instant.
  ///
  /// Web: always null — geolocator_web throws `UnsupportedError` for this
  /// call. Any plugin error also yields null. Coarse and possibly old: a
  /// camera hint, never a pickup.
  Future<GeoPoint?> lastKnownFix() async {
    if (kIsWeb) return null;
    try {
      final position = await Geolocator.getLastKnownPosition();
      if (position == null) return null;
      final point = GeoPoint(position.latitude, position.longitude);
      return point.isValid ? point : null;
    } catch (_) {
      return null;
    }
  }

  /// The app's own last good fix, saved by [saveLastGoodFix]. Works on every
  /// platform, including web. Null on first run or unreadable data.
  Future<GeoPoint?> readLastGoodFix() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(lastGoodFixKey);
      if (raw == null) return null;
      final map = jsonDecode(raw);
      if (map is! Map) return null;
      final lat = (map['lat'] as num?)?.toDouble();
      final lng = (map['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) return null;
      final point = GeoPoint(lat, lng);
      return point.isValid ? point : null;
    } catch (_) {
      return null;
    }
  }

  /// Remembers a successful high-accuracy fix for the next cold start.
  /// Best effort: a storage failure never affects location itself.
  Future<void> saveLastGoodFix(GeoPoint point) async {
    if (!point.isValid) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        lastGoodFixKey,
        jsonEncode({
          'lat': point.latitude,
          'lng': point.longitude,
          'savedAt': DateTime.now().toUtc().toIso8601String(),
        }),
      );
      await prefs.setString(
        lastZoneKey,
        RiderZones.at(point.latitude, point.longitude).id,
      );
    } catch (_) {
      // Best effort only.
    }
  }

  /// The zone of the last good fix ever saved on this device, kept across
  /// sign-out. Null when none was saved or it is unreadable.
  static Future<RiderZone?> readLastZone() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return RiderZones.byId(prefs.getString(lastZoneKey));
    } catch (_) {
      return null;
    }
  }

  /// Forgets the app's last good fix (not [lastZoneKey]). Called when a session ends (sign-out
  /// and session expiry) so the next person using a shared or handed-down
  /// phone never sees the previous rider's last position. Best effort.
  static Future<void> clearLastGoodFix() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(lastGoodFixKey);
    } catch (_) {
      // Best effort only.
    }
  }

  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    return Geolocator.getPositionStream(locationSettings: locationSettings);
  }

  double distanceBetween(
    double startLatitude,
    double startLongitude,
    double endLatitude,
    double endLongitude,
  ) {
    return Geolocator.distanceBetween(
      startLatitude,
      startLongitude,
      endLatitude,
      endLongitude,
    );
  }
}
