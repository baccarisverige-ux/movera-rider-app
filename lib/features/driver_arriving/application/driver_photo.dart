import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/logging/app_log.dart';

/// The driver's approved photo (contract v0.18.5 `riderDriverPhoto`, owner
/// G2-D3 "Yes, approved photo (Recommended)"): loaded from
/// `GET /rider/trips/{tripId}/driver-photo` with the rider's bearer token
/// while the driver comes and during the trip.
///
/// Kept in memory only, never on disk; [clear] drops every photo when the
/// trip ends (no live ride any more) and at sign-out. A 404
/// (`driver_photo_unavailable`) or any failure falls back to the Movera
/// avatar.
abstract final class DriverPhotos {
  static final Map<String, Uint8List> _bytes = {};
  static final Map<String, Future<Uint8List?>> _loading = {};

  /// Bumped by [clear], so a load started for an ended trip is dropped.
  static int _generation = 0;

  /// Tests: the client used instead of the app's.
  @visibleForTesting
  static ApiClient? debugApi;

  /// Only the contract's own path on the API host is opened: the rider's
  /// token never goes to another address.
  static bool isTripPhotoPath(String? path) =>
      path != null &&
      RegExp(r'^/api/v1/rider/trips/[^/?#]+/driver-photo$').hasMatch(path);

  /// The photo already loaded for [path], if any.
  static Uint8List? cached(String? path) => path == null ? null : _bytes[path];

  /// Loads [path] once (concurrent callers share the load).
  static Future<Uint8List?> load(String? path) {
    if (!isTripPhotoPath(path)) return Future.value(null);
    final key = path!;
    final have = _bytes[key];
    if (have != null) return Future.value(have);
    return _loading[key] ??= _fetch(key).whenComplete(() {
      // A block body: returning the removed future would make whenComplete
      // wait for itself.
      _loading.remove(key);
    });
  }

  static Future<Uint8List?> _fetch(String path) async {
    final generation = _generation;
    try {
      final api = debugApi ?? AppScope.instance.api;
      final bytes = await api.getBytes(path);
      if (bytes == null || bytes.isEmpty || generation != _generation) {
        return null;
      }
      final data = Uint8List.fromList(bytes);
      _bytes[path] = data;
      return data;
    } catch (error) {
      AppLog.warning('driver_photo.unavailable', extra: {'error': '$error'});
      return null;
    }
  }

  /// The trip ended or the rider signed out: nothing is kept.
  static void clear() {
    _generation += 1;
    _bytes.clear();
    _loading.clear();
  }

  @visibleForTesting
  static int get heldCount => _bytes.length;
}
