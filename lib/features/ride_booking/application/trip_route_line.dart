import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/core/maps/route_polyline.dart';
import 'package:movera_rider/core/maps/routing_service.dart';
import 'package:movera_rider/core/maps/straight_line.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';
import 'package:movera_rider/shared/styles/route_style.dart';

/// A14 (owner 2026-11-05): the one line a booking map draws for a trip,
/// pickup → every stop in order → destination. Select ride and Finding
/// drivers drew pickup → destination (or straight legs) when the trip had
/// a stop; both now draw this.
typedef TripRouteLine = ({List<LatLng> points, bool approximate});

LatLng _point(RouteStop stop) => LatLng(stop.latitude, stop.longitude);

/// First paint and fallback: straight segments through every stop, never
/// pickup → destination when there are stops.
List<LatLng> straightTripLine(LatLng from, List<RouteStop> stops, LatLng to) =>
    List<LatLng>.unmodifiable([from, ...stops.map(_point), to]);

/// The road line through every stop, one road leg per pair through the
/// shared routing seam ([roadRoutePolylineVia]). [approximate] is true
/// when any leg had no road. Null when routing threw: the caller keeps
/// what it draws.
Future<TripRouteLine?> roadTripLine({
  required LatLng from,
  required List<RouteStop> stops,
  required LatLng to,
  RoutingService? routing,
}) async {
  try {
    final road = await roadRoutePolylineVia(
      id: 'route',
      from: from,
      via: stops.map(_point).toList(growable: false),
      to: to,
      color: RiderRouteStyle.color,
      routing: routing,
    );
    if (road.route.points.length < 2) return null;
    return (
      points: List<LatLng>.unmodifiable(road.route.points),
      approximate: road.approximate,
    );
  } catch (_) {
    return null;
  }
}

/// The quote's distance hint via every stop (straight legs summed), so
/// the hint matches the route that is priced and drawn.
int tripStraightMeters(LatLng from, List<RouteStop> stops, LatLng to) {
  final line = straightTripLine(from, stops, to);
  var total = 0;
  for (var i = 1; i < line.length; i++) {
    total += straightLineMeters(line[i - 1], line[i]);
  }
  return total;
}
