import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/maps/geo_point.dart';

final Expando<ApiClient> _routeApis = Expando<ApiClient>('movera-route-api');
final Expando<Map<String, List<GeoPoint>>> _roadCaches =
    Expando<Map<String, List<GeoPoint>>>('movera-road-cache');

/// rider-u20: the most road lines one [RoutingService] keeps. A live ride
/// asks for a new one every 10 s (the driver's position is in the key), so
/// the least recently used go first instead of the cache growing all day.
const int roadCacheLimit = 32;

/// How many road lines [routing] keeps now.
@visibleForTesting
int roadCacheLengthOf(RoutingService routing) =>
    _roadCaches[routing]?.length ?? 0;

/// The one place a drawn route comes from. Screens must not invent routes.
///
/// [line] stays deliberately synchronous for first paint and for lightweight
/// fakes used throughout the certified Rider test suite.
class RoutingService {
  RoutingService({ApiClient? api}) {
    if (api != null) _routeApis[this] = api;
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
extension RoadRoutingService on RoutingService {
  Future<List<GeoPoint>> roadLine({
    required GeoPoint from,
    required GeoPoint to,
  }) async {
    final cache = _roadCaches[this] ??= <String, List<GeoPoint>>{};
    final key = _roadCacheKey(from, to);
    final cached = cache.remove(key);
    if (cached != null && cached.length >= 2) {
      cache[key] = cached; // Most recently used last.
      return cached;
    }

    final api = _routeApis[this];
    if (api == null) return line(from: from, to: to);

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
      if (raw is! List) return line(from: from, to: to);

      final points = <GeoPoint>[];
      for (final item in raw) {
        if (item is! Map) continue;
        final lat = item['lat'];
        final lng = item['lng'];
        if (lat is num && lng is num) {
          points.add(GeoPoint(lat.toDouble(), lng.toDouble()));
        }
      }
      if (points.length < 2) return line(from: from, to: to);
      cache[key] = points;
      while (cache.length > roadCacheLimit) {
        cache.remove(cache.keys.first);
      }
      return points;
    } catch (_) {
      return line(from: from, to: to);
    }
  }
}

String _roadCacheKey(GeoPoint from, GeoPoint to) {
  String pointKey(GeoPoint point) =>
      '${point.latitude.toStringAsFixed(5)},${point.longitude.toStringAsFixed(5)}';
  return '${pointKey(from)}>${pointKey(to)}';
}
