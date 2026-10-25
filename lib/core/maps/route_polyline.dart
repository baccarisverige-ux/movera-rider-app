import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/maps/routing_service.dart';
import 'package:movera_rider/shared/styles/route_style.dart';

/// Builds the route a screen draws on its map.
///
/// Screens used to hand-build `Polyline(points: [pickup, destination])`, which
/// meant the visible line and [RoutingService] — the app's one route seam —
/// were separate sources of truth. A real Directions provider dropped into
/// [RoutingService] would have changed the stored route and left every screen
/// still drawing its own straight line. Going through here keeps one source.
Polyline routePolyline({
  required String id,
  required LatLng from,
  required LatLng to,
  required Color color,
  int width = 4,
  RoutingService? routing,
}) {
  final service = routing ?? RoutingService.current;
  final points = service.line(
    from: GeoPoint(from.latitude, from.longitude),
    to: GeoPoint(to.latitude, to.longitude),
  );
  return Polyline(
    polylineId: PolylineId(id),
    points: [
      for (final point in points) LatLng(point.latitude, point.longitude),
    ],
    color: color,
    width: width,
  );
}


/// uat-r1: a route a screen already resolved (its kept road points) as the
/// polyline it draws, with the same colour and width rules as
/// [routePolyline], so the road line and the first-paint line are one shape.
Polyline resolvedRoutePolyline({
  required String id,
  required List<LatLng> points,
  required Color color,
  int width = 4,
}) {
  return Polyline(
    polylineId: PolylineId(id),
    points: List<LatLng>.unmodifiable(points),
    color: color,
    width: width,
  );
}

/// Resolves road-following geometry through the shared routing seam and returns
/// a map-ready polyline. Feature screens must use this instead of constructing
/// their own [Polyline], preserving one routing source of truth.
Future<Polyline> roadRoutePolyline({
  required String id,
  required LatLng from,
  required LatLng to,
  required Color color,
  int width = 4,
  RoutingService? routing,
}) async {
  final service = routing ?? RoutingService.current;
  final points = await service.roadLine(
    from: GeoPoint(from.latitude, from.longitude),
    to: GeoPoint(to.latitude, to.longitude),
  );
  return Polyline(
    polylineId: PolylineId(id),
    points: [
      for (final point in points) LatLng(point.latitude, point.longitude),
    ],
    color: color,
    width: width,
  );
}

/// rider-u62/u63: the road route from [from] through every point of [via]
/// (the trip's remaining stops, in order) to [to], one road leg per pair
/// joined into one line. [approximate] is true when any leg fell back to
/// a straight two-point line, so the screen can say the line is not
/// turn-by-turn. Ride check measures "off the route" against this line,
/// so a driver heading to a stop off the direct line is not off route.
Future<({Polyline route, bool approximate})> roadRoutePolylineVia({
  required String id,
  required LatLng from,
  required List<LatLng> via,
  required LatLng to,
  required Color color,
  int width = 4,
  RoutingService? routing,
}) async {
  final service = routing ?? RoutingService.current;
  final waypoints = <LatLng>[from, ...via, to];
  final points = <GeoPoint>[];
  var approximate = false;
  for (var i = 1; i < waypoints.length; i++) {
    final a = waypoints[i - 1];
    final b = waypoints[i];
    final leg = await service.roadLine(
      from: GeoPoint(a.latitude, a.longitude),
      to: GeoPoint(b.latitude, b.longitude),
    );
    if (leg.length <= 2) approximate = true;
    for (final point in leg) {
      final last = points.isEmpty ? null : points.last;
      if (last != null &&
          last.latitude == point.latitude &&
          last.longitude == point.longitude) {
        continue;
      }
      points.add(point);
    }
  }
  return (
    route: Polyline(
      polylineId: PolylineId(id),
      points: [
        for (final point in points) LatLng(point.latitude, point.longitude),
      ],
      color: color,
      width: width,
    ),
    approximate: approximate,
  );
}

/// Number of coloured pieces the green → blue route is drawn with.
const int _routeGradientSteps = 12;

/// Draws [route] the Rider way: a white casing under a line that fades from
/// the green pickup to the blue destination. google_maps_flutter has no
/// gradient polylines, so the line is split into short pieces.
Set<Polyline> styledRoute(Polyline route) {
  final points = route.points;
  final id = route.polylineId.value;
  if (points.length < 2) return {route};
  final width = route.width;
  final pieces = <Polyline>{
    Polyline(
      polylineId: PolylineId('$id-casing'),
      points: points,
      color: RiderRouteStyle.casing,
      width: width + 4,
      zIndex: 1,
    ),
  };
  // Split by distance so the colour change is even along the line.
  final cumulative = <double>[0];
  for (var i = 1; i < points.length; i++) {
    final a = points[i - 1];
    final b = points[i];
    final dLat = b.latitude - a.latitude;
    final dLng = b.longitude - a.longitude;
    cumulative.add(cumulative.last + math.sqrt(dLat * dLat + dLng * dLng));
  }
  final total = cumulative.last;
  if (total == 0) return {route};
  LatLng pointAt(double distance) {
    for (var i = 1; i < points.length; i++) {
      if (cumulative[i] >= distance) {
        final span = cumulative[i] - cumulative[i - 1];
        final f = span == 0 ? 0.0 : (distance - cumulative[i - 1]) / span;
        final a = points[i - 1];
        final b = points[i];
        return LatLng(
          a.latitude + (b.latitude - a.latitude) * f,
          a.longitude + (b.longitude - a.longitude) * f,
        );
      }
    }
    return points.last;
  }

  for (var s = 0; s < _routeGradientSteps; s++) {
    final start = total * s / _routeGradientSteps;
    final end = total * (s + 1) / _routeGradientSteps;
    final piece = <LatLng>[pointAt(start)];
    for (var i = 1; i < points.length - 1; i++) {
      if (cumulative[i] > start && cumulative[i] < end) piece.add(points[i]);
    }
    piece.add(pointAt(end));
    pieces.add(
      Polyline(
        polylineId: PolylineId('$id-$s'),
        points: piece,
        color: RiderRouteStyle.at((s + 0.5) / _routeGradientSteps),
        width: width,
        zIndex: 2,
      ),
    );
  }
  return pieces;
}

/// Owner round 2 (Select ride): the route's dark ink, like the other ride
/// apps.
const Color darkRouteInk = Color(0xFF0B1B2E);

/// [route] drawn as one dark line ([darkRouteInk]) on a thin white edge.
Set<Polyline> darkRoute(Polyline route) {
  if (route.points.length < 2) return {route};
  return {
    Polyline(
      polylineId: PolylineId('${route.polylineId.value}-casing'),
      points: route.points,
      color: Colors.white,
      width: route.width + 3,
      zIndex: 1,
    ),
    route.copyWith(colorParam: darkRouteInk, zIndexParam: 2),
  };
}
