import 'dart:async';

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
import 'package:movera_rider/core/realtime/realtime_connection.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
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

/// G25 step B, whole trip (owner 2026-11-12 "GPS first, then all",
/// BQ-V08): one rider map from searching to the drop-off. #625 pinned
/// searching -> driver found -> arriving; this pins the rest of the trip:
/// driver at the pickup, on board, near the drop-off. The same platform
/// map, the same GoogleMapController object and the same map State (no
/// new initState) all the way, with Waiting owning the camera.
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

  Future<MockRideRealtime> openFinding(
    WidgetTester tester, {
    bool serverLike = false,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const rideId = 'g25s-whole-trip';
    final server = InProcessMockClient();
    final api = ApiClient(client: server);
    final realtime = serverLike
        ? _ServerLikeRealtime(
            assignAfter: const Duration(days: 1),
            api: api,
            connection: AppScope.instance.realtime,
          )
        : MockRideRealtime(assignAfter: const Duration(days: 1), api: api);
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
          home: const Scaffold(body: Center(child: Text('g25s-home'))),
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

  Key? tripMapKeyOf(WidgetTester tester) =>
      tester.widget<CustomGoogleMap>(find.byType(CustomGoogleMap)).key;

  testWidgets('native: searching -> driver found -> en route -> at pickup '
      '-> in trip -> near drop-off keep one map and one controller', (
    tester,
  ) async {
    ParkableMap.debugKeepWhileParked = true;
    CustomGoogleMap.debugMounted.clear();
    final realtime = await openFinding(tester);
    expect(fake.createdIds, hasLength(1), reason: 'searching: its map');
    final first = AppScope.instance.maps.controller;
    expect(first, isNotNull);
    final mapKey = tripMapKeyOf(tester);
    final mountsAtStart = CustomGoogleMap.debugMounted.length;

    void expectSameMap(String stage) {
      expect(fake.createdIds, hasLength(1), reason: '$stage: no new map');
      expect(fake.disposed, isEmpty, reason: '$stage: map not disposed');
      expect(
        find.byType(CustomGoogleMap, skipOffstage: false),
        findsOneWidget,
        reason: '$stage: one map for the trip',
      );
      expect(tripMapKeyOf(tester), same(mapKey), reason: '$stage: same map');
      expect(
        CustomGoogleMap.debugMounted.length,
        mountsAtStart,
        reason: '$stage: the map State was not built again (no re-init)',
      );
      expect(
        AppScope.instance.maps.controller,
        same(first),
        reason: '$stage: same GoogleMapController',
      );
    }

    realtime.assignNow();
    await pumpUntil(
      tester,
      () => find.byType(WaitingForDriver).evaluate().isNotEmpty,
    );
    await pumpUntil(tester, () => false, max: 10);
    expectSameMap('driver found');
    expect(AppScope.instance.maps.activeOwner, MapOwners.waiting);

    final stages = <(String, RideStatus, double, double)>[
      ('en route', RideStatus.driverArriving, 59.3340, 18.0600),
      ('at pickup', RideStatus.driverWaiting, 59.3301, 18.0591),
      ('in trip', RideStatus.tripInProgress, 59.3600, 18.0200),
      ('near drop-off', RideStatus.approachingDropoff, 59.6400, 17.9300),
    ];
    for (final (stage, status, lat, lng) in stages) {
      realtime.emit(status, latitude: lat, longitude: lng);
      await pumpUntil(tester, () => false, max: 10);
      expect(find.byType(WaitingForDriver), findsOneWidget, reason: stage);
      expectSameMap(stage);
      expect(AppScope.instance.maps.activeOwner, MapOwners.waiting);
    }

    realtime.dispose();
    // The camera glides on its own timers: let the last one run out.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(minutes: 1));
  });
}

/// The mock's trip, with the connection behaviour of the server transport
/// (`ApiRideRealtime.subscribe`): the first listener sets the shared
/// connection to "connecting" at once, the first answer to "connected",
/// and the last listener leaving to "disconnected".
class _ServerLikeRealtime extends MockRideRealtime {
  _ServerLikeRealtime({super.assignAfter, super.api, super.connection});

  @override
  Stream<RideRealtimeEvent> subscribe(String rideId) {
    final inner = super.subscribe(rideId);
    StreamSubscription<RideRealtimeEvent>? feed;
    late final StreamController<RideRealtimeEvent> out;
    out = StreamController<RideRealtimeEvent>.broadcast(
      onListen: () {
        connection.state = RealtimeState.connecting;
        feed = inner.listen(out.add, onError: out.addError);
        scheduleMicrotask(() {
          if (out.hasListener) connection.markConnected();
        });
      },
      onCancel: () {
        unawaited(feed?.cancel());
        connection.markDisconnected();
        unawaited(out.close());
      },
    );
    return out.stream;
  }
}
