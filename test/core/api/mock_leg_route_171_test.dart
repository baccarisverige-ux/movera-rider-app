import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/realtime/leg_route_hub.dart';

/// v0.18.171 demo: the demo transport's trip reads carry a sample
/// legRoute (to the pickup once a driver holds the trip, to the drop-off
/// on trip). Off by default, so no test depends on it.
void main() {
  Future<Map<String, dynamic>> read(InProcessMockClient client) async {
    final response = await client.get(
      Uri.parse('https://api.demo.movera.invalid/api/v1/rides/r171'),
    );
    return (jsonDecode(response.body) as Map<String, dynamic>)['ride']
        as Map<String, dynamic>;
  }

  Map<String, dynamic> ride(String status) => {
    'id': 'r171',
    'status': status,
    'driverLat': 59.34,
    'driverLng': 18.05,
    'pickupLat': 59.3326,
    'pickupLng': 18.0649,
    'destinationLat': 59.3143,
    'destinationLng': 18.0735,
  };

  test('the demo sends a pickup line, then a drop-off line', () async {
    final demo = InProcessMockClient(legRouteSample: true);
    demo.rides['r171'] = ride('driver_to_pickup');
    final toPickup = LegRoute.tryParse((await read(demo))['legRoute']);
    expect(toPickup?.target, 'pickup');
    expect(toPickup!.points.length, greaterThan(2));
    demo.rides['r171'] = ride('in_trip');
    final toDropoff = LegRoute.tryParse((await read(demo))['legRoute']);
    expect(toDropoff?.target, 'dropoff');
    demo.rides['r171'] = ride('arrived');
    expect((await read(demo)).containsKey('legRoute'), isFalse);
    expect(demo.rides['r171']!.containsKey('legRoute'), isFalse);
  });

  test('off by default (tests never rely on it)', () async {
    final plain = InProcessMockClient();
    plain.rides['r171'] = ride('driver_to_pickup');
    expect((await read(plain)).containsKey('legRoute'), isFalse);
  });
}
