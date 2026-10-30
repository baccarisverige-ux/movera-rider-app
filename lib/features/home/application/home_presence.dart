import 'dart:async';

import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/ride_selection/data/nearby_cars_repository.dart';

/// Contract v0.18.4 §29 `driverHome.ridersOnline` (owner G3-R4 "Real
/// numbers only"; live test 2026-10-30: a rider with the app open on Home
/// was not counted online). The server counts a rider online in a zone
/// while he asks for the cars near him (`GET /rider/nearby-vehicles`) or a
/// price there; Home asked for neither. While Home is on screen and the
/// rider is signed in, Home asks for the cars near his position every
/// [every], well inside the server's window.
class HomePresence {
  HomePresence({
    required Future<void> Function(GeoPoint point) ping,
    required GeoPoint? Function() position,
    required Future<bool> Function() signedIn,
    this.every = defaultEvery,
    this.noFixRetry = defaultNoFixRetry,
  }) : _ping = ping,
       _position = position,
       _signedIn = signedIn;

  /// The server's `GET /rider/nearby-vehicles` at the rider's position
  /// (the answer, the cars, is not drawn on Home).
  static Future<void> Function(GeoPoint point) nearbyCars(ApiClient api) {
    final cars = NearbyCarsRepository(api);
    return (point) => cars.near(point);
  }

  /// Inside `ridersOnline.windowSeconds` (120 s) with room for a slow
  /// answer; the server writes at most once per 30 s per rider.
  static const defaultEvery = Duration(seconds: 45);

  /// No position yet: asked again this soon, not a whole [every] later.
  static const defaultNoFixRetry = Duration(seconds: 5);

  final Future<void> Function(GeoPoint point) _ping;
  final GeoPoint? Function() _position;
  final Future<bool> Function() _signedIn;
  final Duration every;
  final Duration noFixRetry;

  Timer? _timer;
  bool _running = false;
  bool _inFlight = false;
  bool _disposed = false;

  bool get running => _running;

  /// Home is on screen: asks now, then every [every].
  void start() {
    if (_running || _disposed) return;
    _running = true;
    unawaited(_tick());
  }

  /// Home is covered, the app is in the background, or Home closes.
  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    _disposed = true;
    stop();
  }

  Future<void> _tick() async {
    _timer?.cancel();
    _timer = null;
    if (!_running || _inFlight) return;
    var wait = every;
    _inFlight = true;
    try {
      final point = _position();
      if (point == null) {
        wait = noFixRetry;
      } else if (await _signedIn() && _running) {
        await _ping(point);
      }
    } catch (error) {
      // No connection or a refused call: the next tick tries again.
      AppLog.warning('home.presence_failed', extra: {'error': '$error'});
    } finally {
      _inFlight = false;
    }
    if (_running && !_disposed) {
      _timer = Timer(wait, () => unawaited(_tick()));
    }
  }
}
