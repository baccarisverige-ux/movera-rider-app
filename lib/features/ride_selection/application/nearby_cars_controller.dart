import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/features/ride_selection/data/nearby_cars_repository.dart';
import 'package:movera_rider/features/ride_selection/domain/nearby_car.dart';

/// Where one car is drawn right now.
@immutable
class NearbyCarFrame {
  const NearbyCarFrame({
    required this.key,
    required this.latitude,
    required this.longitude,
    this.heading,
  });

  final String key;
  final double latitude;
  final double longitude;
  final double? heading;
}

class _Track {
  _Track(
    this.fromLat,
    this.fromLng,
    this.toLat,
    this.toLng,
    this.heading,
    this.startedAt,
  );

  double fromLat;
  double fromLng;
  double toLat;
  double toLng;
  double? heading;
  DateTime startedAt;

  double progress(DateTime now, Duration glide) {
    if (glide <= Duration.zero) return 1;
    final t = now.difference(startedAt).inMicroseconds / glide.inMicroseconds;
    return t.clamp(0.0, 1.0);
  }

  ({double lat, double lng}) at(DateTime now, Duration glide) {
    final t = _ease(progress(now, glide));
    return (
      lat: fromLat + (toLat - fromLat) * t,
      lng: fromLng + (toLng - fromLng) * t,
    );
  }
}

/// Ease in and out, so a car speeds up and slows down between answers.
double _ease(double t) => t < 0.5 ? 2 * t * t : 1 - math.pow(-2 * t + 2, 2) / 2;

/// The free cars around the pickup on Select ride (contract v0.5.2 §13).
///
/// Asks the server every `refreshSeconds` while [watch]ing, never two
/// requests at once, and backs off after failures (a failure keeps the cars
/// it had). Each car glides from where it is drawn to its new position over
/// [glide], so the map shows smooth movement between answers; a jump of more
/// than [jumpMeters] is drawn at once.
class NearbyCarsController extends ChangeNotifier {
  NearbyCarsController({
    required NearbyCarsSource source,
    DateTime Function()? clock,
    this.glide = const Duration(milliseconds: 1400),
  }) : _source = source,
       _clock = clock ?? DateTime.now;

  /// The server's `GET /rider/nearby-vehicles` (contract v0.5.2 §13).
  static NearbyCarsSource apiSource(ApiClient api) => NearbyCarsRepository(api);

  final NearbyCarsSource _source;
  final DateTime Function() _clock;
  final Duration glide;

  static const double jumpMeters = 1000;

  /// A pickup moved by more than this starts over (the old cars are dropped).
  static const double newAreaMeters = 600;

  final Map<String, _Track> _tracks = <String, _Track>{};
  GeoPoint? _point;
  bool _active = false;
  bool _inFlight = false;
  bool _disposed = false;
  int _generation = 0;
  int _failures = 0;
  Timer? _next;

  bool get watching => _active;

  /// Starts (or moves) the watch to [point].
  void watch(GeoPoint point) {
    if (_disposed) return;
    final previous = _point;
    final moved =
        previous == null ||
        _meters(
              previous.latitude,
              previous.longitude,
              point.latitude,
              point.longitude,
            ) >
            30;
    if (!moved && _active) return;
    if (previous != null &&
        _meters(
              previous.latitude,
              previous.longitude,
              point.latitude,
              point.longitude,
            ) >
            newAreaMeters &&
        _tracks.isNotEmpty) {
      _tracks.clear();
      notifyListeners();
    }
    _point = point;
    if (moved) _generation++;
    _active = true;
    unawaited(_fetch());
  }

  /// Stops asking (the screen is covered or leaving); the cars stay drawn.
  void pause() {
    _active = false;
    _next?.cancel();
    _next = null;
  }

  /// Asks again at once after a [pause].
  void resume() {
    if (_disposed || _active || _point == null) return;
    _active = true;
    unawaited(_fetch());
  }

  Future<void> _fetch() async {
    _next?.cancel();
    _next = null;
    final point = _point;
    if (_inFlight || !_active || _disposed || point == null) return;
    _inFlight = true;
    final generation = _generation;
    var wait = NearbyCarsRepository.defaultRefresh;
    try {
      final answer = await _source.near(point);
      if (_disposed) return;
      if (generation == _generation) {
        _apply(answer.cars);
        _failures = 0;
      }
      wait = answer.refresh;
    } catch (error) {
      if (_disposed) return;
      _failures += 1;
      if (_failures == 1) {
        AppLog.warning(
          'select_ride.nearby_cars_failed',
          extra: {'error': '$error'},
        );
      }
      wait = Duration(seconds: math.min(30, 5 * _failures));
    } finally {
      _inFlight = false;
    }
    if (_disposed || !_active) return;
    // The pickup moved while this answer was on its way: ask for the new
    // place at once.
    if (generation != _generation) wait = Duration.zero;
    _next = Timer(wait, () => unawaited(_fetch()));
  }

  void _apply(List<NearbyCar> cars) {
    final now = _clock();
    final keys = <String>{};
    for (final car in cars) {
      keys.add(car.key);
      final track = _tracks[car.key];
      if (track == null) {
        _tracks[car.key] = _Track(
          car.latitude,
          car.longitude,
          car.latitude,
          car.longitude,
          car.heading,
          now,
        );
        continue;
      }
      final here = track.at(now, glide);
      final distance = _meters(here.lat, here.lng, car.latitude, car.longitude);
      track
        ..fromLat = distance > jumpMeters ? car.latitude : here.lat
        ..fromLng = distance > jumpMeters ? car.longitude : here.lng
        ..toLat = car.latitude
        ..toLng = car.longitude
        ..startedAt = now
        ..heading =
            car.heading ??
            (distance > 5
                ? _bearing(here.lat, here.lng, car.latitude, car.longitude)
                : track.heading);
    }
    _tracks.removeWhere((key, _) => !keys.contains(key));
    notifyListeners();
  }

  /// The cars where they are drawn at [now] (defaults to the clock).
  List<NearbyCarFrame> frames([DateTime? now]) {
    final at = now ?? _clock();
    return [
      for (final entry in _tracks.entries)
        () {
          final p = entry.value.at(at, glide);
          return NearbyCarFrame(
            key: entry.key,
            latitude: p.lat,
            longitude: p.lng,
            heading: entry.value.heading,
          );
        }(),
    ];
  }

  /// Whether any car is still on its way to its latest position.
  bool gliding([DateTime? now]) {
    final at = now ?? _clock();
    for (final track in _tracks.values) {
      final still =
          track.fromLat == track.toLat && track.fromLng == track.toLng;
      if (!still && track.progress(at, glide) < 1) return true;
    }
    return false;
  }

  @override
  void dispose() {
    _disposed = true;
    _next?.cancel();
    _next = null;
    super.dispose();
  }

  static double _meters(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    double rad(double d) => d * math.pi / 180;
    final dLat = rad(lat2 - lat1);
    final dLng = rad(lng2 - lng1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(rad(lat1)) *
            math.cos(rad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _bearing(double lat1, double lng1, double lat2, double lng2) {
    double rad(double d) => d * math.pi / 180;
    final y = math.sin(rad(lng2 - lng1)) * math.cos(rad(lat2));
    final x =
        math.cos(rad(lat1)) * math.sin(rad(lat2)) -
        math.sin(rad(lat1)) * math.cos(rad(lat2)) * math.cos(rad(lng2 - lng1));
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }
}
