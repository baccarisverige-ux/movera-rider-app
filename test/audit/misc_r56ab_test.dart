import 'dart:async';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/api/safety_mock_api.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/maps/map_camera_motion.dart';
import 'package:movera_rider/core/maps/routing_service.dart';
import 'package:movera_rider/core/web/rider_map_bridge.dart';
import 'package:shared_preferences/shared_preferences.dart';
/// A [Random] that always answers [value].
class _FixedRandom implements Random {
  _FixedRandom(this.value);
  final int value;
  @override
  int nextInt(int max) => value % max;
  @override
  double nextDouble() => 0;
  @override
  bool nextBool() => false;
}

/// Takes camera moves instead of driving a platform map.
class _FakeMap extends Fake implements GoogleMapController {
  @override
  Future<void> moveCamera(CameraUpdate cameraUpdate) => Future<void>.value();
}

/// R5.6 parts a and b: small local fixes, one short test per bug.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('rider-u13: chained pickup moves after accept are measured from '
      'the accepted pickup', () async {
    // Driver on the way; each move is about 300 m north of the last one.
    final mock = InProcessMockClient();
    mock.rides['ride-chain'] = {
      'id': 'ride-chain',
      'status': 'driverArriving',
      'pickupAddress': 'Start',
      'pickupLat': 59.3326,
      'pickupLng': 18.0649,
      'destinationAddress': 'Odenplan 2',
      'destinationLat': 59.3426,
      'destinationLng': 18.0498,
      'price': 200.0,
      'bookedPrice': 200.0,
      'bookedKm': 1.4,
      'stops': <Map<String, dynamic>>[],
      'version': 3,
    };
    final api = ApiClient(client: mock);
    Future<void> moveTo(String name, double lat) => api.patch(
      '/api/v1/rides/ride-chain',
      body: {
        'routeChange': true,
        'pickupAddress': name,
        'pickupLat': lat,
        'pickupLng': 18.0649,
        'destinationAddress': 'Odenplan 2',
        'destinationLat': 59.3426,
        'destinationLng': 18.0498,
        'stops': const <Object>[],
      },
    );
    await moveTo('First', 59.3353);
    await expectLater(
      moveTo('Second', 59.3380),
      throwsA(
        isA<ApiError>().having((e) => e.detail, 'detail', 'pickup_too_far'),
      ),
    );
    expect(mock.rides['ride-chain']!['pickupAddress'], 'First');
  });

  test('rider-u16: the demo safety PIN comes from a random source, not '
      'the clock', () {
    final before = SafetyMockApi.pinRandom;
    addTearDown(() => SafetyMockApi.pinRandom = before);
    SafetyMockApi.pinRandom = _FixedRandom(4321);
    expect((SafetyMockApi()..reset()).pin['pin'], '4321');
  });

  testWidgets('rider-j8-15: a recenter during a follow glide flies on the '
      'web frame clock', (tester) async {
    final flights = <CameraPosition>[];
    RiderMapBridge.debugFlight = (_, to, _) {
      flights.add(to);
      return Future.value(true);
    };
    addTearDown(() => RiderMapBridge.debugFlight = null);
    final fake = _FakeMap();
    mapViewOf(fake)
      ..mapId = 1
      ..pose = const CameraPosition(target: LatLng(59.33, 18.06), zoom: 13);
    unawaited(
      easeCameraTo(
        fake,
        const CameraPosition(target: LatLng(59.331, 18.06), zoom: 13),
      ),
    );
    await tester.pump(cameraEaseFrame);
    const recenter = CameraPosition(target: LatLng(59.34, 18.07), zoom: 15);
    unawaited(easeCameraTo(fake, recenter, duration: cameraFlightDuration));
    await tester.pump(cameraEaseFrame);
    expect(flights, [recenter]);
    mapViewOf(fake).interrupt();
    await tester.pump(cameraEaseFrame);
  });

  test('rider-u20: the road-route cache stays bounded on a long ride', () async {
    final routing = RoutingService(api: ApiClient(client: InProcessMockClient()));
    const pickup = GeoPoint(59.3326, 18.0649);
    // A driver moving: every 10 s refresh has a new origin.
    for (var i = 0; i < roadCacheLimit + 20; i++) {
      await routing.roadLine(from: GeoPoint(59.30 + i * 0.0001, 18.06), to: pickup);
    }
    expect(roadCacheLengthOf(routing), roadCacheLimit);
  });
}
