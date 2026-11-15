import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/core/maps/geo_point.dart';

/// Where a past ride's line comes from (contract v0.17.0 §25,
/// `contract.json#tripPath`, `TripPath.source`).
enum TripPathSource {
  /// Thinned from the trip's own GPS trace (what the car really drove).
  driven,

  /// The server's road route from the pickup through the stops to the
  /// drop-off: the trace was deleted after 30 days, or none was sent.
  planned,
}

/// BQ-V16 (owner driver-g11.md:6, "must be for all apps live trip or
/// history including admin"): the route of an ended trip for the rider's
/// past-ride map, read from `GET /trips/{tripId}/path`.
class TripPath {
  const TripPath({
    required this.source,
    required this.points,
    required this.pickup,
    required this.dropoff,
    this.stops = const <GeoPoint>[],
  });

  final TripPathSource source;
  final List<GeoPoint> points;
  final GeoPoint pickup;
  final GeoPoint dropoff;
  final List<GeoPoint> stops;

  /// A contract `TripPath`; null when it is not one (an unknown source,
  /// fewer than two valid points, a missing pickup or drop-off).
  static TripPath? fromJson(Map<String, dynamic> json) {
    final source = switch (json['source']) {
      'driven' => TripPathSource.driven,
      'planned' => TripPathSource.planned,
      _ => null,
    };
    final pickup = _point(json['pickup']);
    final dropoff = _point(json['dropoff']);
    final raw = json['points'];
    if (source == null || pickup == null || dropoff == null || raw is! List) {
      return null;
    }
    final points = <GeoPoint>[];
    for (final item in raw) {
      final p = _point(item);
      if (p == null) return null;
      points.add(p);
    }
    if (points.length < 2) return null;
    final rawStops = json['stops'];
    return TripPath(
      source: source,
      points: List.unmodifiable(points),
      pickup: pickup,
      dropoff: dropoff,
      stops: List.unmodifiable([
        if (rawStops is List)
          for (final item in rawStops) ?_point(item),
      ]),
    );
  }

  static GeoPoint? _point(Object? value) {
    if (value is! Map) return null;
    final lat = value['lat'];
    final lng = value['lng'];
    if (lat is! num || lng is! num) return null;
    final p = GeoPoint(lat.toDouble(), lng.toDouble());
    return p.isValid ? p : null;
  }

  /// Reads the trip's route; null on the mock transport (demo keeps its
  /// drawing) and on any failure (the map then shows the pins only).
  static Future<TripPath?> load(String tripId, {ApiClient? api}) async {
    final client = api ?? AppScope.instance.api;
    if (!client.contractWire || tripId.trim().isEmpty) return null;
    try {
      return fromJson(await client.get(client.tripPath(tripId, 'path')));
    } catch (error) {
      AppLog.warning(
        'ride.path.not_read',
        extra: {'rideId': tripId, 'error': '$error'},
      );
      return null;
    }
  }
}
