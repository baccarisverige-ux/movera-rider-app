import 'package:flutter/foundation.dart';
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

  /// v0.18.169: the encoded line of each kept trip, so a booked trip can
  /// keep it with the saved ride (RideSnapshot.routePolyline).
  static final Map<String, String> _encoded = <String, String>{};

  /// v0.18.169 (contract.json#riderTripRouteLine, SHOULD): the newest
  /// quote answer that set or dropped the line of each trip. An older
  /// answer that lands later never brings its line back.
  static final Map<String, int> _tickets = <String, int>{};
  static int _ticket = 0;

  /// Tickets handed out before the last [clear] (sign-out) are stale.
  static int _floor = 0;

  /// How many trips have a ticket kept (tests).
  @visibleForTesting
  static int get ticketCount => _tickets.length;

  /// A ticket for one quote request, taken before it is sent.
  static int nextTicket() => ++_ticket;

  /// False when [ticket] is older than the last change of [key] or than
  /// the last [clear]; records it otherwise.
  static bool _fresh(String key, int? ticket) {
    if (ticket == null) return true;
    if (ticket <= _floor || ticket < (_tickets[key] ?? 0)) return false;
    // Newest last, so the trim below drops the oldest trips first.
    _tickets.remove(key);
    _tickets[key] = ticket;
    // v0.18.169 (review SHOULD 3): trimmed with the kept lines, so the
    // map stays small; a trip trimmed here has no kept line to protect.
    while (_tickets.length > limit * 2) {
      final oldest = _tickets.keys.first;
      _tickets.remove(oldest);
      _routes.remove(oldest);
      _encoded.remove(oldest);
    }
    return true;
  }

  /// Keeps [encoded] as the road line of the trip [waypoints] (pickup, every
  /// stop, drop-off). An empty line is not kept; a broken one (it does not
  /// decode) drops the line kept before, so the map never shows an older
  /// line (v0.18.169 SHOULD). [ticket] ([nextTicket]) orders answers.
  /// True when the line is kept.
  static bool remember(List<LatLng> waypoints, String? encoded, {int? ticket}) {
    if (waypoints.length < 2 || encoded == null || encoded.isEmpty) {
      return false;
    }
    final key = _key(waypoints);
    if (!_fresh(key, ticket)) return false;
    final points = decodeGooglePolyline(encoded);
    _routes.remove(key);
    _encoded.remove(key);
    if (points == null || points.length < 2) return false;
    _routes[key] = List<LatLng>.unmodifiable(points);
    _encoded[key] = encoded;
    while (_routes.length > limit) {
      final oldest = _routes.keys.first;
      _encoded.remove(oldest);
      _tickets.remove(oldest);
      _routes.remove(oldest);
    }
    return true;
  }

  /// The kept Google line of the trip [waypoints], or null.
  static List<LatLng>? of(List<LatLng> waypoints) =>
      waypoints.length < 2 ? null : _routes[_key(waypoints)];

  /// The kept line of the trip [waypoints] as Google encoded it, or null.
  static String? encodedOf(List<LatLng> waypoints) =>
      waypoints.length < 2 ? null : _encoded[_key(waypoints)];

  /// Drops the kept line of the trip [waypoints]: a newer quote of the
  /// same trip came back without a Google line (an estimate), so its maps
  /// draw the straight line again (follow-up 2026-11-26). A stale
  /// [ticket] drops nothing.
  static void forget(List<LatLng> waypoints, {int? ticket}) {
    final key = _key(waypoints);
    if (!_fresh(key, ticket)) return;
    _routes.remove(key);
    _encoded.remove(key);
  }

  /// Forgets every kept line (sign-out wipe, follow-up 2026-11-26; tests).
  /// A quote asked before it never brings a line back (v0.18.169).
  static void clear() {
    _routes.clear();
    _encoded.clear();
    _tickets.clear();
    _floor = _ticket;
  }

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
