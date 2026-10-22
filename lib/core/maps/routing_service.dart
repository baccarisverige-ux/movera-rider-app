import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/maps/web_road_route.dart';

final Expando<ApiClient> _routeApis = Expando<ApiClient>('movera-route-api');
final Expando<Map<String, List<GeoPoint>>> _roadCaches =
    Expando<Map<String, List<GeoPoint>>>('movera-road-cache');
final Expando<PublicRoadRouter> _publicRoads = Expando<PublicRoadRouter>(
  'movera-public-road',
);
final Expando<Map<String, Future<List<GeoPoint>>>> _roadRequests =
    Expando<Map<String, Future<List<GeoPoint>>>>('movera-road-requests');

/// rider-u20: the most road lines one [RoutingService] keeps. A live ride
/// asks for a new one every 10 s (the driver's position is in the key), so
/// the least recently used go first instead of the cache growing all day.
const int roadCacheLimit = 32;

/// uat-r1: how long one public road request may take (a slow mobile
/// network answers late, not never), how many times a leg is asked for
/// before the direct line is drawn, and the pause between those attempts.
const Duration publicRoadTimeout = Duration(seconds: 8);
const int publicRoadAttempts = 2;
const Duration publicRoadRetryAfter = Duration(milliseconds: 400);

/// Road geometry from a public router, or null when nothing usable came
/// back (the caller decides whether to ask again).
typedef PublicRoadRouter =
    Future<List<GeoPoint>?> Function(
      GeoPoint from,
      GeoPoint to, {
      Duration timeout,
    });

/// How many road lines [routing] keeps now.
@visibleForTesting
int roadCacheLengthOf(RoutingService routing) =>
    _roadCaches[routing]?.length ?? 0;

/// The one place a drawn route comes from. Screens must not invent routes.
///
/// [line] stays deliberately synchronous for first paint and for lightweight
/// fakes used throughout the certified Rider test suite.
class RoutingService {
  /// uat-r1: [allowPublicRoadFallback] is the web demo's switch (like
  /// `AppGeocoding.allowPublicReverseFallback`): its in-process transport
  /// answers `/api/v1/routes` with the two end points only, which every
  /// booking map drew as a straight line. With the switch on, and only on
  /// the web, a two-point answer is completed by [publicRoad]. Release
  /// builds never reach a public router.
  RoutingService({
    ApiClient? api,
    bool allowPublicRoadFallback = false,
    PublicRoadRouter? publicRoad,
    bool? isWeb,
  }) {
    if (api != null) _routeApis[this] = api;
    if (allowPublicRoadFallback && (isWeb ?? kIsWeb)) {
      _publicRoads[this] = publicRoad ?? openSourceRoutingMachineRoute;
    }
  }

  /// Composition hook: app/di registers the app's routing service here so
  /// core helpers can default to it without importing the DI container
  /// (ARCH-17). Unregistered, the direct-line service is used.
  static RoutingService Function()? defaultProvider;

  static RoutingService get current =>
      defaultProvider?.call() ?? RoutingService();

  List<GeoPoint> line({required GeoPoint from, required GeoPoint to}) => [
    from,
    to,
  ];
}

/// Road geometry is requested through Movera's authenticated API boundary.
///
/// Rider never sends pickup/dropoff coordinates directly to an uncontrolled
/// public routing provider. The backend may choose and rotate its route
/// provider without exposing provider credentials or Rider network metadata.
/// (The web demo's public fallback is the one documented exception; see
/// [RoutingService.new].)
extension RoadRoutingService on RoutingService {
  Future<List<GeoPoint>> roadLine({
    required GeoPoint from,
    required GeoPoint to,
  }) {
    final cache = _roadCaches[this] ??= <String, List<GeoPoint>>{};
    final key = _roadCacheKey(from, to);
    final cached = cache.remove(key);
    if (cached != null && cached.length >= 2) {
      cache[key] = cached; // Most recently used last.
      return Future<List<GeoPoint>>.value(cached);
    }

    // uat-r1: Select Ride and Finding ask for the same leg within a
    // second of each other; they share one request.
    final requests = _roadRequests[this] ??= <String, Future<List<GeoPoint>>>{};
    final running = requests[key];
    if (running != null) return running;
    final request = _resolveRoad(from, to, key: key, cache: cache);
    requests[key] = request;
    return request.whenComplete(() => requests.remove(key));
  }

  Future<List<GeoPoint>> _resolveRoad(
    GeoPoint from,
    GeoPoint to, {
    required String key,
    required Map<String, List<GeoPoint>> cache,
  }) async {
    var points = await _controlledRoad(from, to);
    final public = _publicRoads[this];
    var fromPublic = false;
    if (public != null && (points == null || points.length < 3)) {
      final road = await _publicRoad(public, from, to);
      if (road != null) {
        points = road;
        fromPublic = true;
      } else if (points != null) {
        // The public router had nothing this time: draw the direct line
        // now, and ask again on the next request rather than keeping it.
        return points;
      }
    }
    if (points == null || points.length < 2) return line(from: from, to: to);
    if (public == null || fromPublic) {
      cache[key] = points;
      while (cache.length > roadCacheLimit) {
        cache.remove(cache.keys.first);
      }
    }
    return points;
  }

  /// The controlled API's answer, or null when it failed or was unusable.
  Future<List<GeoPoint>?> _controlledRoad(GeoPoint from, GeoPoint to) async {
    final api = _routeApis[this];
    if (api == null) return null;
    try {
      final json = await api.post(
        '/api/v1/routes',
        body: <String, dynamic>{
          'mode': 'driving',
          'from': <String, double>{
            'lat': from.latitude,
            'lng': from.longitude,
          },
          'to': <String, double>{
            'lat': to.latitude,
            'lng': to.longitude,
          },
        },
      );
      final raw = json['points'];
      if (raw is! List) return null;

      final points = <GeoPoint>[];
      for (final item in raw) {
        if (item is! Map) continue;
        final lat = item['lat'];
        final lng = item['lng'];
        if (lat is num && lng is num) {
          points.add(GeoPoint(lat.toDouble(), lng.toDouble()));
        }
      }
      return points.length < 2 ? null : points;
    } catch (_) {
      return null;
    }
  }

  /// One leg from the public router: [publicRoadAttempts] tries, each
  /// bounded by [publicRoadTimeout], so one slow or dropped answer on a
  /// phone network is not drawn as a straight line.
  Future<List<GeoPoint>?> _publicRoad(
    PublicRoadRouter public,
    GeoPoint from,
    GeoPoint to,
  ) async {
    for (var attempt = 1; attempt <= publicRoadAttempts; attempt += 1) {
      try {
        final road = await public(from, to, timeout: publicRoadTimeout);
        if (road != null && road.length >= 2) return road;
      } catch (_) {
        // A timeout or a network error: asked once more below.
      }
      if (attempt < publicRoadAttempts) {
        await Future<void>.delayed(publicRoadRetryAfter);
      }
    }
    return null;
  }
}

String _roadCacheKey(GeoPoint from, GeoPoint to) {
  String pointKey(GeoPoint point) =>
      '${point.latitude.toStringAsFixed(5)},${point.longitude.toStringAsFixed(5)}';
  return '${pointKey(from)}>${pointKey(to)}';
}
