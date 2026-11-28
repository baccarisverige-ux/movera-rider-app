import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart'
    show GoogleMapsFlutterPlatform;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/maps/routing_service.dart';
import 'package:movera_rider/core/realtime/leg_route_hub.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/auth/application/user_data_wipe.dart';
import 'package:movera_rider/features/driver_arriving/application/driver_tracking_controller.dart';
import 'package:movera_rider/features/finding_driver/domain/driver_eta.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/shared/widgets/custom_google_map.dart';

import '../fixtures/fake_maps_platform.dart';
import 'leg_route_171_fixtures.dart';

/// v0.18.171 (contract.json#googleRoadLines.rider): Waiting for driver and
/// the on-trip map draw the leg's stored Google line (no POST /routes, no
/// "approximate" badge), cut at the car; the other leg's line is never
/// drawn; on trip the order is the drop-off legRoute, then
/// TripProjection.routePolyline, then POST /routes; the car more than
/// 200 m from the line falls back to the old path; the line is dropped on
/// a leg switch, a route change, a different trip and sign-out.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  const tripId = 'trp_171';
  const staging = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://api.example.test',
  );

  late GoogleMapsFlutterPlatform previousMaps;
  late int routeCalls;
  Completer<void>? postGate;

  setUp(() {
    LegRouteHub.clear();
    previousMaps = GoogleMapsFlutterPlatform.instance;
    GoogleMapsFlutterPlatform.instance = FakeMapsPlatform();
    CustomGoogleMap.debugWaitForMaps = false;
    routeCalls = 0;
    postGate = null;
    final routing = RoutingService(
      api: ApiClient(
        env: staging,
        client: MockClient((request) async {
          if (request.method == 'POST' &&
              request.url.path.endsWith('/routes')) {
            routeCalls++;
            final gate = postGate;
            if (gate != null) await gate.future;
          }
          return http.Response('{}', 500);
        }),
      ),
    );
    RoutingService.defaultProvider = () => routing;
  });
  tearDown(() {
    RoutingService.defaultProvider = null;
    CustomGoogleMap.debugWaitForMaps = null;
    GoogleMapsFlutterPlatform.instance = previousMaps;
    LegRouteHub.clear();
  });

  DriverTrackingController tracking(RideStatus status, LatLng car) {
    final t = DriverTrackingController(
      realtime: MockRideRealtime(api: ApiClient(client: InProcessMockClient())),
      pickupLat: pickupPoint.latitude,
      pickupLng: pickupPoint.longitude,
      destinationLat: dropoffPoint.latitude,
      destinationLng: dropoffPoint.longitude,
      persistRideSnapshot: false,
    );
    t.status = status;
    t.eta = DriverEta(
      seconds: 240,
      latitude: car.latitude,
      longitude: car.longitude,
    );
    return t;
  }

  Future<void> pumpMap(
    WidgetTester tester,
    DriverTrackingController t, {
    String? rideId = tripId,
    LatLng destination = dropoffPoint,
    ValueChanged<List<GeoPoint>>? onTripRoute,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => MaterialApp(
          home: Scaffold(
            body: debugWaitingRideMap(
              tracking: t,
              rideId: rideId,
              pickup: pickupPoint,
              destination: destination,
              onTripRoute: onTripRoute,
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  List<LatLng> drawn(WidgetTester tester) {
    final map = tester.widget<CustomGoogleMap>(find.byType(CustomGoogleMap));
    final casing = map.polylines!.where(
      (line) => line.polylineId.value == 'active-road-route-casing',
    );
    return casing.isEmpty ? const [] : casing.single.points;
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(minutes: 1));
  }

  testWidgets('a valid pickup legRoute: drawn cut at the car, zero POST '
      '/routes, no approximate badge', (tester) async {
    LegRouteHub.offerLeg(tripId, LegRoute.tryParse(pickupLegJson())!);
    await pumpMap(tester, tracking(RideStatus.driverArriving, carPoint));
    expect(routeCalls, 0);
    expect(drawn(tester), pickupLegPoints);
    expect(find.text('Approximate route'), findsNothing);
    final map = tester.widget<CustomGoogleMap>(find.byType(CustomGoogleMap));
    expect(
      {for (final line in map.polylines!) line.color.toARGB32()},
      everyElement(anyOf(0xFF12201C, 0xFF2FBF5B)),
      reason: 'no blue',
    );
    // More redraws while the line is shown: still no route request.
    LegRouteHub.offerLeg(tripId, LegRoute.tryParse(pickupLegJson())!);
    await settle(tester);
    expect(routeCalls, 0);
    await unmount(tester);
  });

  testWidgets('no line at first (POST /routes as today), then the event\'s '
      'line is drawn without another request', (tester) async {
    await pumpMap(tester, tracking(RideStatus.driverArriving, carPoint));
    final before = routeCalls;
    expect(before, greaterThan(0), reason: 'the old path without a line');
    LegRouteHub.offerLeg(tripId, LegRoute.tryParse(pickupLegJson())!);
    await settle(tester);
    expect(drawn(tester), pickupLegPoints);
    expect(routeCalls, before);
    await unmount(tester);
  });

  testWidgets('a legRoute for the other leg is not drawn', (tester) async {
    LegRouteHub.offerLeg(tripId, LegRoute.tryParse(dropoffLegJson())!);
    await pumpMap(tester, tracking(RideStatus.driverArriving, carPoint));
    expect(routeCalls, greaterThan(0));
    // The old path's line (the POST /routes fallback), not the other leg.
    expect(drawn(tester), [carPoint, pickupPoint]);
    await unmount(tester);
    // On trip, a pickup line is not drawn either.
    LegRouteHub.clear();
    LegRouteHub.offerLeg(tripId, LegRoute.tryParse(pickupLegJson())!);
    routeCalls = 0;
    await pumpMap(tester, tracking(RideStatus.tripInProgress, pickupPoint));
    expect(routeCalls, greaterThan(0));
    expect(drawn(tester), [pickupPoint, dropoffPoint]);
    await unmount(tester);
  });

  testWidgets('a late POST /routes answer never replaces the stored line', (
    tester,
  ) async {
    postGate = Completer<void>();
    await pumpMap(tester, tracking(RideStatus.driverArriving, carPoint));
    expect(routeCalls, 1, reason: 'the POST is on its way');
    LegRouteHub.offerLeg(tripId, LegRoute.tryParse(pickupLegJson())!);
    await settle(tester);
    expect(drawn(tester), pickupLegPoints);
    // The delayed answer lands after the Google line was drawn.
    postGate!.complete();
    await settle(tester);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await settle(tester);
    expect(drawn(tester), pickupLegPoints, reason: 'the line stays');
    await unmount(tester);
  });

  testWidgets('on trip the order is legRoute drop-off, then routePolyline, '
      'then POST /routes', (tester) async {
    const otherShape = <LatLng>[
      pickupPoint,
      LatLng(59.3250, 18.0600),
      LatLng(59.3180, 18.0650),
      dropoffPoint,
    ];
    LegRouteHub.offerTripLine(tripId, otherShape);
    LegRouteHub.offerLeg(tripId, LegRoute.tryParse(dropoffLegJson())!);
    await pumpMap(tester, tracking(RideStatus.tripInProgress, pickupPoint));
    expect(drawn(tester), dropoffLegPoints, reason: '1: legRoute drop-off');
    LegRouteHub.dropLeg(tripId);
    await settle(tester);
    expect(drawn(tester), otherShape, reason: '2: routePolyline');
    expect(routeCalls, 0);
    LegRouteHub.dropTrip(tripId);
    await settle(tester);
    await unmount(tester);
    await pumpMap(tester, tracking(RideStatus.tripInProgress, pickupPoint));
    expect(routeCalls, greaterThan(0), reason: '3: POST /routes');
    expect(drawn(tester), [pickupPoint, dropoffPoint]);
    await unmount(tester);
  });

  testWidgets('the map shows the line cut at the car', (tester) async {
    LegRouteHub.offerLeg(tripId, LegRoute.tryParse(pickupLegJson())!);
    // Between the 2nd and 3rd points of the line.
    const car = LatLng(59.3380, 18.0580);
    await pumpMap(tester, tracking(RideStatus.driverArriving, car));
    final line = drawn(tester);
    expect(line.first, car);
    expect(line.last, pickupPoint);
    expect(line, isNot(contains(carPoint)), reason: 'the part behind is gone');
    expect(line, isNot(contains(pickupLegPoints[1])));
    expect(line, containsAllInOrder(pickupLegPoints.sublist(2)));
    expect(routeCalls, 0);
    await unmount(tester);
  });

  testWidgets('on trip: the drop-off legRoute, fed to onTripRoute, zero '
      'POST /routes', (tester) async {
    final fed = <List<GeoPoint>>[];
    LegRouteHub.offerLeg(tripId, LegRoute.tryParse(dropoffLegJson())!);
    await pumpMap(
      tester,
      tracking(RideStatus.tripInProgress, pickupPoint),
      onTripRoute: fed.add,
    );
    expect(routeCalls, 0);
    expect(drawn(tester), dropoffLegPoints);
    expect(fed, isNotEmpty);
    expect(fed.last, hasLength(dropoffLegPoints.length));
    await unmount(tester);
  });

  testWidgets('on trip without a legRoute: routePolyline, then POST '
      '/routes', (tester) async {
    LegRouteHub.offerTripLine(tripId, dropoffLegPoints);
    await pumpMap(tester, tracking(RideStatus.tripInProgress, pickupPoint));
    expect(routeCalls, 0);
    expect(drawn(tester), dropoffLegPoints);
    await unmount(tester);
    LegRouteHub.clear();
    await pumpMap(tester, tracking(RideStatus.tripInProgress, pickupPoint));
    expect(routeCalls, greaterThan(0));
    await unmount(tester);
  });

  testWidgets('the car 500 m from the line falls back to the old path', (
    tester,
  ) async {
    LegRouteHub.offerLeg(tripId, LegRoute.tryParse(pickupLegJson())!);
    // About 500 m north of the line's start.
    await pumpMap(
      tester,
      tracking(RideStatus.driverArriving, const LatLng(59.3445, 18.0500)),
    );
    expect(routeCalls, greaterThan(0));
    expect(drawn(tester), isNot(pickupLegPoints));
    await unmount(tester);
  });

  testWidgets('a leg switch drops the pickup line', (tester) async {
    LegRouteHub.offerLeg(tripId, LegRoute.tryParse(pickupLegJson())!);
    final t = tracking(RideStatus.driverArriving, carPoint);
    await pumpMap(tester, t);
    expect(drawn(tester), pickupLegPoints);
    t.status = RideStatus.tripInProgress;
    // Any new stored line redraws the map.
    LegRouteHub.offerTripLine('another-trip', dropoffLegPoints);
    await settle(tester);
    expect(LegRouteHub.legOf(tripId), isNull);
    await unmount(tester);
  });

  testWidgets('a route change keeps a freshly received line and never '
      'draws the old route\'s line', (tester) async {
    const newDropoff = LatLng(59.3080, 18.0800);
    final newLine = <LatLng>[
      pickupPoint,
      const LatLng(59.3200, 18.0760),
      newDropoff,
    ];
    final t = tracking(RideStatus.tripInProgress, pickupPoint);
    LegRouteHub.offerLeg(tripId, LegRoute.tryParse(dropoffLegJson())!);
    await pumpMap(tester, t);
    expect(drawn(tester), dropoffLegPoints);
    // The new route's line arrives just before the screen rebuilds.
    LegRouteHub.offerLeg(
      tripId,
      LegRoute.tryParse({
        'target': 'dropoff',
        'polyline': encodeLine(newLine),
      })!,
    );
    await pumpMap(tester, t, destination: newDropoff);
    expect(LegRouteHub.legOf(tripId), isNotNull, reason: 'kept');
    expect(drawn(tester), newLine);
    await unmount(tester);

    // The old route's line (ends at the old drop-off) is not drawn.
    LegRouteHub.offerLeg(tripId, LegRoute.tryParse(dropoffLegJson())!);
    await pumpMap(tester, t, destination: newDropoff);
    expect(drawn(tester), isNot(dropoffLegPoints));
    expect(routeCalls, greaterThan(0));
    await unmount(tester);
  });

  testWidgets('a different trip drops the old trip\'s lines', (tester) async {
    LegRouteHub.offerLeg(tripId, LegRoute.tryParse(pickupLegJson())!);
    final t = tracking(RideStatus.driverArriving, carPoint);
    await pumpMap(tester, t);
    await pumpMap(tester, t, rideId: 'trp_other');
    expect(LegRouteHub.legOf(tripId), isNull);
    await unmount(tester);
  });

  test('sign-out forgets the lines', () {
    LegRouteHub.offerLeg(tripId, LegRoute.tryParse(pickupLegJson())!);
    LegRouteHub.offerTripLine(tripId, dropoffLegPoints);
    UserDataWipe.resetInMemory();
    expect(LegRouteHub.legOf(tripId), isNull);
    expect(LegRouteHub.tripLineOf(tripId), isNull);
  });

  test('the cut starts at the car and keeps the line ahead', () {
    final cut = cutLineAtCar(pickupLegPoints, const GeoPoint(59.3380, 18.0580));
    expect(cut, isNotNull);
    expect(cut!.first, const LatLng(59.3380, 18.0580));
    expect(cut.last, pickupPoint);
    expect(cut.length, lessThan(pickupLegPoints.length + 2));
    expect(cut, isNot(contains(carPoint)), reason: 'the part behind is cut');
    expect(
      cutLineAtCar(pickupLegPoints, const GeoPoint(59.3445, 18.05)),
      isNull,
    );
  });
}
