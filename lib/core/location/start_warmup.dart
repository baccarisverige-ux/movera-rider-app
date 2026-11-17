import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:geolocator/geolocator.dart';
import 'package:movera_rider/core/location/location_repository.dart';
import 'package:movera_rider/core/maps/geo_point.dart';

/// Owner job "Fast start behind the intro" (REMINDERS 144/145): the
/// position search starts the moment the intro starts, not when Home is
/// built. One request only: Home takes this one ([takePosition]) instead of
/// asking again (battery).
///
/// Never asks: not signed in, location off, or permission not given yet
/// (first time, refused) do nothing here; Home keeps today's flows.
class StartWarmup {
  StartWarmup._();

  /// A warm request older than this is not handed to Home (it may be a
  /// Home built long after start, for example after a trip).
  static const maxAge = Duration(seconds: 30);

  /// Same bounds as Home's own accurate fix (D-003: the Dart timeout also
  /// bounds the web plugin).
  static const fixTimeout = Duration(seconds: 16);

  static Future<Position>? _position;
  static DateTime? _startedAt;
  static GeoPoint? _hint;
  static bool _granted = false;

  /// Whether the warmup found a signed-in rider with location allowed.
  static bool get granted => _granted;

  /// Where Home's map opens: an active trip's point wins, then this
  /// session's fix, then the warm or saved fix. Null when nothing is known.
  static GeoPoint? startPoint({GeoPoint? trip}) =>
      trip ?? LocationRepository.sessionFix ?? _hint;

  static Future<void> start({
    required LocationRepository location,
    required Future<bool> Function() signedIn,
  }) async {
    if (_startedAt != null) return;
    _startedAt = DateTime.now();
    try {
      if (!await signedIn()) return;
      if (!await location.isLocationServiceEnabled()) return;
      final permission = await location.checkPermission();
      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        return;
      }
      _granted = true;
      final position = location
          .getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 15),
            ),
          )
          .timeout(fixTimeout);
      _position = position;
      unawaited(
        position.then<void>((p) {
          final point = GeoPoint(p.latitude, p.longitude);
          if (point.isValid) _hint = point;
        }, onError: (Object _) {}),
      );
      final saved =
          await location.readLastGoodFix() ?? await location.lastKnownFix();
      if (saved != null) _hint ??= saved;
    } catch (_) {
      // Best effort: Home finds the position as before.
    }
  }

  /// The warm position request, once (later calls get null), while fresh.
  static Future<Position>? takePosition() {
    final position = _position;
    final at = _startedAt;
    _position = null;
    if (position == null || at == null) return null;
    if (DateTime.now().difference(at) > maxAge) return null;
    return position;
  }

  /// The session ended (sign-out): the next rider never sees this one's
  /// position. A new start may warm again.
  static void forget() {
    _position = null;
    _hint = null;
    _granted = false;
  }

  @visibleForTesting
  static void debugReset() {
    _position = null;
    _startedAt = null;
    _hint = null;
    _granted = false;
  }
}
