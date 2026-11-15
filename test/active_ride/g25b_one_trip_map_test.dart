import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/router/routes.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/maps/map_owners.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/active_ride/presentation/driver_cancelled_notice.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/presentation/finding_drivers.dart';
import 'package:movera_rider/features/ride_booking/application/ride_restore_coordinator.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/shared/widgets/custom_google_map.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';
import 'package:movera_rider/shared/widgets/parkable_map.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fixtures/fake_maps_platform.dart';

/// G25 step B (owner 2026-11-12 "GPS first, then all", BQ-V08): the rider
/// app built a new Google map at "driver found" (Finding pushed Waiting,
/// each with its own map): a blank surface, then a zoom jump. On a phone
/// the trip now has one map: searching, driver found, driver arriving and
/// back to searching after a driver drop all show the same platform map,
/// and each screen still owns the camera while it is on top.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  late FakeMapsPlatform fake;
  late GoogleMapsFlutterPlatform previousMaps;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    RideSnapshotStore.epoch = 0;
    FindingDriverController.active = null;
    previousMaps = GoogleMapsFlutterPlatform.instance;
    fake = FakeMapsPlatform();
    GoogleMapsFlutterPlatform.instance = fake;
    CustomGoogleMap.debugWaitForMaps = false;
  });
  tearDown(() {
    CustomGoogleMap.debugWaitForMaps = null;
    ParkableMap.debugKeepWhileParked = null;
    GoogleMapsFlutterPlatform.instance = previousMaps;
  });

  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() done, {
    int max = 80,
  }) async {
    for (var i = 0; i < max && !done(); i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<MockRideRealtime> openFinding(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const rideId = 'g25b-one-map';
    final server = InProcessMockClient();
    final api = ApiClient(client: server);
    final realtime = MockRideRealtime(
      assignAfter: const Duration(days: 1),
      api: api,
    );
    addTearDown(realtime.dispose);
    server.rides[rideId] = {'id': rideId, 'status': 'findingDriver'};
    RideRestoreCoordinator.instance.showing = RestoredSurface.home;
    AppScope.instance.ride
      ..rideId = rideId
      ..status = RideStatus.findingDriver
      ..suppressRestore = false
      ..authoritativeVersion = null
      ..authoritativeUpdatedAt = null;
    final controller = FindingDriverController(realtime: realtime, api: api);
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(375, 812),
        minTextAdapt: true,
        splitScreenMode: true,
        builder: (_, __) => MaterialApp(
          navigatorKey: nav,
          home: const Scaffold(body: Center(child: Text('g25b-home'))),
        ),
      ),
    );
    nav.currentState!.push(
      RideStageTransition(
        FindingDrivers(
          pickupAddress: 'Stockholm Central',
          destinationAddress: 'Arlanda Airport',
          pickupPosition: const LatLng(59.33, 18.059),
          destinationPosition: const LatLng(59.6519, 17.9186),
          rideType: 'Movera',
          price: 349,
          paymentMethod: 'Apple Pay',
          realtime: realtime,
          controller: controller,
        ),
        settings: const RouteSettings(name: AppRoutes.findingDriver),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(FindingDrivers), findsOneWidget);
    return realtime;
  }

  Future<void> driverFoundThenArriving(
    WidgetTester tester,
    MockRideRealtime realtime,
  ) async {
    realtime.assignNow();
    await pumpUntil(
      tester,
      () => find.byType(WaitingForDriver).evaluate().isNotEmpty,
    );
    expect(find.byType(WaitingForDriver), findsOneWidget);
    await pumpUntil(tester, () => false, max: 10);
    realtime.emit(
      RideStatus.driverArriving,
      latitude: 59.3340,
      longitude: 18.0600,
    );
    await pumpUntil(tester, () => false, max: 10);
  }

  testWidgets('native: searching -> driver found -> driver arriving -> '
      'searching again use one platform map', (tester) async {
    ParkableMap.debugKeepWhileParked = true;
    final realtime = await openFinding(tester);
    expect(fake.createdIds, hasLength(1), reason: 'searching: its map');
    expect(AppScope.instance.maps.activeOwner, MapOwners.finding);

    await driverFoundThenArriving(tester, realtime);
    expect(
      fake.createdIds,
      hasLength(1),
      reason: 'driver found / arriving: no new map (G25 reload)',
    );
    expect(fake.disposed, isEmpty);
    expect(
      find.byType(CustomGoogleMap, skipOffstage: false),
      findsOneWidget,
      reason: 'the trip has one map, not one per screen',
    );
    expect(AppScope.instance.maps.activeOwner, MapOwners.waiting);
    expect(AppScope.instance.maps.ownerStack, isNot(contains('finding')));
    // The map shows Waiting's trip: the driver's car is drawn on it.
    final markers = tester
        .widget<CustomGoogleMap>(find.byType(CustomGoogleMap))
        .markers!;
    expect(markers.map((m) => m.markerId.value), contains('driver'));

    // A driver drop: back to the search, on the same map.
    realtime.holdAssignment();
    realtime.cancelByDriver();
    await pumpUntil(
      tester,
      () => find.byType(WaitingForDriver).evaluate().isEmpty,
    );
    await pumpUntil(tester, () => false, max: 10);
    expect(find.byType(FindingDrivers), findsOneWidget);
    expect(fake.createdIds, hasLength(1), reason: 'searching again');
    expect(fake.disposed, isEmpty);
    expect(AppScope.instance.maps.activeOwner, MapOwners.finding);
    expect(AppScope.instance.maps.ownerStack, isNot(contains('waiting')));

    // The next driver: still the same map.
    realtime.assignNow();
    await pumpUntil(
      tester,
      () => find.byType(WaitingForDriver).evaluate().isNotEmpty,
    );
    await pumpUntil(tester, () => false, max: 10);
    expect(fake.createdIds, hasLength(1), reason: 'second driver found');
    expect(AppScope.instance.maps.activeOwner, MapOwners.waiting);

    realtime.dispose();
    await tester.pump(driverCancelledNoticeDuration);
    await tester.pumpAndSettle();
  });

  testWidgets('native: a Waiting opened on its own (a reservation\'s live '
      'trip, a restored trip) builds its own map and owns it', (tester) async {
    ParkableMap.debugKeepWhileParked = true;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final realtime = MockRideRealtime(assignAfter: const Duration(days: 1));
    addTearDown(realtime.dispose);
    realtime.subscribe('g25b-own-map');
    realtime.assignNow();
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(375, 812),
        minTextAdapt: true,
        splitScreenMode: true,
        builder: (_, __) => MaterialApp(
          home: WaitingForDriver(
            pickupAddress: 'Stockholm Central',
            destinationAddress: 'Arlanda Airport',
            pickupPosition: const LatLng(59.33, 18.059),
            destinationPosition: const LatLng(59.6519, 17.9186),
            rideType: 'Movera',
            price: 349,
            paymentMethod: 'Apple Pay',
            driver: realtime.lastDriver,
            realtime: realtime,
            rideId: 'g25b-own-map',
            persistRideSnapshot: false,
          ),
        ),
      ),
    );
    await pumpUntil(tester, () => false, max: 10);
    expect(fake.createdIds, hasLength(1));
    expect(find.byKey(const ValueKey('waiting-map')), findsOneWidget);
    expect(AppScope.instance.maps.activeOwner, MapOwners.waiting);
    realtime.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('web: unchanged, Waiting builds its own map (the page pools '
      'maps)', (tester) async {
    ParkableMap.debugKeepWhileParked = false;
    final realtime = await openFinding(tester);
    await driverFoundThenArriving(tester, realtime);
    expect(fake.createdIds, hasLength(2));
    expect(AppScope.instance.maps.activeOwner, MapOwners.waiting);
    realtime.dispose();
    await tester.pumpAndSettle();
  });
}
