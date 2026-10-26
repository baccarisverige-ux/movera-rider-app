import 'dart:math' as math;

import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/performance/performance_budgets.dart';

class MarkerRecord {
  const MarkerRecord({required this.id, required this.point, this.heading = 0});

  final String id;
  final GeoPoint point;
  final double heading;
}

/// Stable IDs. Tiny GPS/heading jitter is ignored so native map markers are not
/// rebuilt at sensor cadence.
class MarkerStore {
  MarkerStore({
    this.minimumMoveMeters = PerformanceBudgets.markerMinimumMoveMeters,
    this.minimumHeadingDegrees = PerformanceBudgets.markerMinimumHeadingDegrees,
  });

  final double minimumMoveMeters;
  final double minimumHeadingDegrees;
  final Map<String, MarkerRecord> _markers = {};

  MarkerRecord upsert(String id, GeoPoint point, {double heading = 0}) {
    final existing = _markers[id];
    if (existing != null &&
        _metersBetween(existing.point, point) < minimumMoveMeters &&
        _headingDelta(existing.heading, heading) < minimumHeadingDegrees) {
      return existing;
    }

    final record = MarkerRecord(id: id, point: point, heading: heading);
    _markers[id] = record;
    return record;
  }

  void remove(String id) => _markers.remove(id);

  MarkerRecord? operator [](String id) => _markers[id];

  Iterable<MarkerRecord> get values => _markers.values;
}

double _headingDelta(double a, double b) {
  final raw = (a - b).abs() % 360;
  return math.min(raw, 360 - raw);
}

double _metersBetween(GeoPoint a, GeoPoint b) {
  const earthRadius = 6371000.0;
  final lat1 = a.latitude * math.pi / 180;
  final lat2 = b.latitude * math.pi / 180;
  final dLat = (b.latitude - a.latitude) * math.pi / 180;
  final dLng = (b.longitude - a.longitude) * math.pi / 180;
  final sinLat = math.sin(dLat / 2);
  final sinLng = math.sin(dLng / 2);
  final h = sinLat * sinLat + math.cos(lat1) * math.cos(lat2) * sinLng * sinLng;
  return earthRadius * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
}
