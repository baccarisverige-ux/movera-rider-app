import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/core/maps/geo_distance.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/maps/route_polyline.dart';
import 'package:movera_rider/core/maps/routing_service.dart';

/// rider-u62 / rider-u63: during the trip the drawn road route, and the
/// planned route Ride check measures "off route" against, went straight
/// from the driver to the destination and ignored the trip's stops (booked
/// or added). A driver correctly heading to a stop more than 2 km off that
/// line opened a false "off route" Ride check, and the line skipped the
/// stop on the map.
class _RoadRouting extends RoutingService {
  int legs = 0;

  @override
  List<GeoPoint> line({required GeoPoint from, required GeoPoint to}) {
    legs += 1;
    // A "road" leg: a bend half way, so it is more than two points.
    return [
      from,
      GeoPoint(
        (from.latitude + to.latitude) / 2 + 0.001,
        (from.longitude + to.longitude) / 2,
      ),
      to,
    ];
  }
}

void main() {
  const driver = LatLng(59.3293, 18.0686);
  const destination = LatLng(59.3626, 18.0649);
  // About 3 km east of the direct line.
  const stop = LatLng(59.3460, 18.1200);

  double metersOff(LatLng point, List<LatLng> route) {
    var best = double.infinity;
    for (final vertex in route) {
      final meters = GeoDistance.metersBetween(
        point.latitude,
        point.longitude,
        vertex.latitude,
        vertex.longitude,
      );
      if (meters < best) best = meters;
    }
    return best;
  }

  test('the in-trip road route runs through the remaining stops', () async {
    final routing = _RoadRouting();
    final resolved = await roadRoutePolylineVia(
      id: 'trip',
      from: driver,
      via: const [stop],
      to: destination,
      color: Colors.blue,
      routing: routing,
    );

    expect(routing.legs, 2, reason: 'driver > stop, stop > destination');
    expect(resolved.approximate, isFalse);
    final points = resolved.route.points;
    expect(points.first, driver);
    expect(points.last, destination);
    expect(points, contains(stop));
    expect(metersOff(stop, points), 0);
    // Joined legs share the stop once.
    expect(points.where((p) => p == stop), hasLength(1));
  });

  test(
    'a straight-line fallback on any leg marks the route approximate',
    () async {
      final resolved = await roadRoutePolylineVia(
        id: 'trip',
        from: driver,
        via: const [stop],
        to: destination,
        color: Colors.blue,
        routing: RoutingService(),
      );
      expect(resolved.approximate, isTrue);
      expect(resolved.route.points, [driver, stop, destination]);
    },
  );

  test(
    'without stops the route is the single driver-to-destination leg',
    () async {
      final routing = _RoadRouting();
      final resolved = await roadRoutePolylineVia(
        id: 'trip',
        from: driver,
        via: const [],
        to: destination,
        color: Colors.blue,
        routing: routing,
      );
      expect(routing.legs, 1);
      // The old single-leg route ran this far from the stop: a driver going
      // there was "off route".
      expect(metersOff(stop, resolved.route.points), greaterThan(2000));
    },
  );
}
