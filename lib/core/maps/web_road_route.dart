import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:movera_rider/core/maps/geo_point.dart';

/// Road geometry between two points from a public router, used on the web
/// demo where the in-process transport knows no roads (it answers
/// `/api/v1/routes` with the two end points, which drew as a straight line).
/// Returns null when nothing usable comes back; the caller decides whether
/// to ask again.
///
/// Mirrors `openStreetMapReverse`: demo-only, and only reached through
/// `RoutingService` with its public fallback switched on.
Future<List<GeoPoint>?> openSourceRoutingMachineRoute(
  GeoPoint from,
  GeoPoint to, {
  Duration timeout = const Duration(seconds: 8),
  http.Client? client,
}) async {
  String coord(GeoPoint point) =>
      '${point.longitude.toStringAsFixed(6)},${point.latitude.toStringAsFixed(6)}';
  final uri = Uri.https(
    'router.project-osrm.org',
    '/route/v1/driving/${coord(from)};${coord(to)}',
    {
      'overview': 'full',
      'geometries': 'geojson',
      'alternatives': 'false',
      'steps': 'false',
    },
  );
  final http.Client c = client ?? http.Client();
  try {
    final response = await c
        .get(uri, headers: const {'Accept': 'application/json'})
        .timeout(timeout);
    if (response.statusCode != 200) return null;
    return parseOsrmRoute(response.body);
  } catch (_) {
    return null;
  } finally {
    if (client == null) c.close();
  }
}

/// The first route's geojson line as lat/lng points, or null when [body]
/// is not an "Ok" OSRM answer with at least two points.
List<GeoPoint>? parseOsrmRoute(String body) {
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } catch (_) {
    return null;
  }
  if (decoded is! Map || decoded['code'] != 'Ok') return null;
  final routes = decoded['routes'];
  if (routes is! List || routes.isEmpty) return null;
  final first = routes.first;
  if (first is! Map) return null;
  final geometry = first['geometry'];
  if (geometry is! Map) return null;
  final coordinates = geometry['coordinates'];
  if (coordinates is! List) return null;
  final points = <GeoPoint>[];
  for (final pair in coordinates) {
    if (pair is! List || pair.length < 2) continue;
    final lng = pair[0];
    final lat = pair[1];
    if (lat is num && lng is num) {
      points.add(GeoPoint(lat.toDouble(), lng.toDouble()));
    }
  }
  return points.length < 2 ? null : points;
}
