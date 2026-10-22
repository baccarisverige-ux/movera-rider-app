import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/api/safety_mock_api.dart';
import 'package:movera_rider/core/location/location_point.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/maps/map_camera_motion.dart';
import 'package:movera_rider/core/maps/routing_service.dart';
import 'package:movera_rider/core/motion/motion_engine.dart';
import 'package:movera_rider/core/web/rider_map_bridge.dart';
import 'package:movera_rider/features/active_ride/application/route_change_controller.dart';
import 'package:movera_rider/features/active_ride/presentation/route_change_sheet.dart';
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

/// Pumps [child] alone on a phone-sized screen.
Future<void> _pumpPage(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  await tester.pump();
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

  test('rider-20: the home puck glides to a new fix over the window', () {
    final engine = MotionEngine();
    final t0 = DateTime(2026, 10, 22, 12);
    LocationPoint fix(double lat, DateTime at) => LocationPoint(
      point: GeoPoint(lat, 18.06),
      timestamp: at,
      accuracyMeters: 5,
    );
    engine.ingest(fix(59.3300, t0), now: t0);
    // The next fix arrives a second later (1 Hz GPS).
    final t1 = t0.add(const Duration(seconds: 1));
    final start = engine.ingest(fix(59.3310, t1), now: t1)!;
    final half = engine.poseAt(t1.add(MotionEngine.window ~/ 2))!;
    final end = engine.poseAt(t1.add(MotionEngine.window))!;
    expect(start.position.latitude, closeTo(59.3300, 1e-9));
    expect(half.position.latitude, closeTo(59.3305, 1e-9));
    expect(end.position.latitude, closeTo(59.3310, 1e-9));
    expect(end.progress, 1);
  });

  testWidgets('rider-u43: a 0.40 EUR route change is not "Same price" and '
      'asks for the card step', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await _pumpPage(
      tester,
      const RouteChangeSheet(
        quote: RouteChangeQuote(
          pickupAddress: 'Rue de Rivoli 1',
          pickupPoint: GeoPoint(48.86, 2.34),
          destinationAddress: 'Gare du Nord',
          destinationPoint: GeoPoint(48.88, 2.355),
          stops: [],
          oldPriceKr: 18.20,
          newPriceKr: 18.60,
          currency: 'EUR',
        ),
        paymentMethod: 'Visa •••• 4242',
      ),
    );
    expect(find.text('Same price as before.'), findsNothing);
    expect(find.text('Confirm · next: payment'), findsOneWidget);
  });
}
