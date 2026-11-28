import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/core/maps/geo_distance.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/maps/quoted_route.dart';

/// v0.18.170 / v0.18.171 (contract.json#riderLegRouteLine,
/// contract.json#googleRoadLines.rider): the stored Google road line of the
/// trip's current leg. `target` is `pickup` (the driver is coming) or
/// `dropoff` (on trip).
class LegRoute {
  const LegRoute({required this.target, required this.points});

  /// `pickup` or `dropoff`.
  final String target;
  final List<LatLng> points;

  bool get toPickup => target == 'pickup';

  /// `{target, polyline}` (TripProjection.legRoute or TripEta.legRoute),
  /// else null: an unknown target, a polyline that does not decode, or
  /// one with fewer than 2 points is ignored.
  static LegRoute? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final target = raw['target'];
    final polyline = raw['polyline'];
    if (target != 'pickup' && target != 'dropoff') return null;
    if (polyline is! String || polyline.isEmpty) return null;
    final points = decodeGooglePolyline(polyline);
    if (points == null || points.length < 2) return null;
    return LegRoute(
      target: target as String,
      points: List<LatLng>.unmodifiable(points),
    );
  }
}

/// The road lines the trip reads and the location events carried, per
/// trip. Kept in memory only: never in the saved ride (RideSnapshot), so
/// nothing of it outlives the process or a sign-out.
abstract final class LegRouteHub {
  static final Map<String, LegRoute> _legs = {};
  static final Map<String, List<LatLng>> _tripLines = {};

  /// Bumped on every change; the trip map listens and redraws.
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  static LegRoute? legOf(String tripId) => _legs[tripId.trim()];

  /// TripProjection.routePolyline of [tripId] (pickup to drop-off), the
  /// on-trip map's line when no drop-off legRoute was sent.
  static List<LatLng>? tripLineOf(String tripId) => _tripLines[tripId.trim()];

  /// The newest legRoute wins.
  static void offerLeg(String tripId, LegRoute leg) {
    _legs[tripId.trim()] = leg;
    changes.value++;
  }

  static void offerTripLine(String tripId, List<LatLng> points) {
    if (points.length < 2) return;
    _tripLines[tripId.trim()] = List<LatLng>.unmodifiable(points);
    changes.value++;
  }

  /// Driver change, back to searching, terminal status: the leg is gone.
  static void dropLeg(String tripId) {
    if (_legs.remove(tripId.trim()) != null) changes.value++;
  }

  /// Route change: neither line is this trip's route any more.
  static void dropTrip(String tripId) {
    final id = tripId.trim();
    final hadLeg = _legs.remove(id) != null;
    final hadLine = _tripLines.remove(id) != null;
    if (hadLeg || hadLine) changes.value++;
  }

  /// Sign-out.
  static void clear() {
    if (_legs.isEmpty && _tripLines.isEmpty) return;
    _legs.clear();
    _tripLines.clear();
    changes.value++;
  }
}

/// How far the car may be from a stored line before the map falls back
/// to the old path (contract.json#googleRoadLines.rider: 200 m).
const double legRouteMaxOffMeters = 200;

/// [line] cut from the point nearest [car]: the car, then the rest of the
/// line ahead of it. Null when the car is more than [maxOffMeters] from
/// the line (the caller keeps its old path).
List<LatLng>? cutLineAtCar(
  List<LatLng> line,
  GeoPoint car, {
  double maxOffMeters = legRouteMaxOffMeters,
}) {
  if (line.length < 2) return null;
  final cosLat = math.cos(car.latitude * math.pi / 180);
  const metersPerDegree = 111320.0;
  // Local flat metres around the car: good enough over a city.
  ({double x, double y}) flat(LatLng p) => (
    x: (p.longitude - car.longitude) * metersPerDegree * cosLat,
    y: (p.latitude - car.latitude) * metersPerDegree,
  );
  var best = double.infinity;
  var bestSegment = 0;
  LatLng? bestPoint;
  for (var i = 0; i < line.length - 1; i++) {
    final a = flat(line[i]);
    final b = flat(line[i + 1]);
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    final length2 = dx * dx + dy * dy;
    final t = length2 == 0
        ? 0.0
        : ((-a.x * dx - a.y * dy) / length2).clamp(0.0, 1.0);
    final px = a.x + dx * t;
    final py = a.y + dy * t;
    final distance = math.sqrt(px * px + py * py);
    if (distance < best) {
      best = distance;
      bestSegment = i;
      bestPoint = LatLng(
        line[i].latitude + (line[i + 1].latitude - line[i].latitude) * t,
        line[i].longitude + (line[i + 1].longitude - line[i].longitude) * t,
      );
    }
  }
  if (best > maxOffMeters || bestPoint == null) return null;
  final start = LatLng(car.latitude, car.longitude);
  final rest = line.sublist(bestSegment + 1);
  final cut = <LatLng>[start];
  final snapMeters = GeoDistance.metersBetween(
    car.latitude,
    car.longitude,
    bestPoint.latitude,
    bestPoint.longitude,
  );
  if (snapMeters > 1) cut.add(bestPoint);
  cut.addAll(rest);
  return cut.length >= 2 ? List<LatLng>.unmodifiable(cut) : null;
}
