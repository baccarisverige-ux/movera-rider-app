import 'package:google_maps_flutter/google_maps_flutter.dart';

/// v0.18.167 (contract.json#googleRouteLine, owner 2026-11-26 "Oui,
/// corriger"): the Google route the server priced a quote on
/// (`Quote.routePolyline`, only when `routeSource` is google). Select ride
/// keeps it here when the quotes come in, and every booking map that draws
/// the same trip (Select ride, Finding drivers) reads it instead of the
/// straight line, with no new route call (owner: about 2 Google calls per
/// trip). Nothing kept = the old straight line + "Approximate route".
class QuotedRoutes {
  QuotedRoutes._();

  /// The most trips kept (a rider prices a few routes per session).
  static const int limit = 8;

  static final Map<String, List<LatLng>> _routes = <String, List<LatLng>>{};

  /// Keeps [encoded] as the road line of the trip [waypoints] (pickup, every
  /// stop, drop-off). An empty or broken line is not kept.
  static void remember(List<LatLng> waypoints, String? encoded) {
    if (waypoints.length < 2 || encoded == null || encoded.isEmpty) return;
    final points = decodeGooglePolyline(encoded);
    if (points == null || points.length < 2) return;
    final key = _key(waypoints);
    _routes.remove(key);
    _routes[key] = List<LatLng>.unmodifiable(points);
    while (_routes.length > limit) {
      _routes.remove(_routes.keys.first);
    }
  }

  /// The kept Google line of the trip [waypoints], or null.
  static List<LatLng>? of(List<LatLng> waypoints) =>
      waypoints.length < 2 ? null : _routes[_key(waypoints)];

  /// Tests only.
  static void clear() => _routes.clear();

  static String _key(List<LatLng> waypoints) => waypoints
      .map(
        (p) =>
            '${p.latitude.toStringAsFixed(5)},${p.longitude.toStringAsFixed(5)}',
      )
      .join('>');
}

/// Decodes a Google encoded polyline (precision 5), or null when it is
/// malformed (a cut string, a value out of range).
List<LatLng>? decodeGooglePolyline(String encoded) {
  final points = <LatLng>[];
  var index = 0;
  var lat = 0;
  var lng = 0;
  int? next() {
    var result = 0;
    var shift = 0;
    while (true) {
      if (index >= encoded.length) return null;
      final b = encoded.codeUnitAt(index++) - 63;
      if (b < 0 || b > 63) return null;
      result |= (b & 0x1f) << shift;
      shift += 5;
      if (b < 0x20) break;
      if (shift > 30) return null;
    }
    return (result & 1) != 0 ? ~(result >> 1) : result >> 1;
  }

  while (index < encoded.length) {
    final dLat = next();
    final dLng = next();
    if (dLat == null || dLng == null) return null;
    lat += dLat;
    lng += dLng;
    final la = lat / 1e5;
    final ln = lng / 1e5;
    if (la.abs() > 90 || ln.abs() > 180) return null;
    points.add(LatLng(la, ln));
  }
  return points;
}
