import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/router/routes.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/active_ride/presentation/driver_cancelled_notice.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/presentation/finding_drivers.dart';
import 'package:movera_rider/features/ride_booking/application/ride_restore_coordinator.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    RideSnapshotStore.epoch = 0;
    FindingDriverController.active = null;
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

  testWidgets('RIDE-8 / rider-u93: after a driver drop the search uses the '
      'route, price and offer ceiling changed on Waiting', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const rideId = 'research-route';
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
      ..authoritativeUpdatedAt = null
      // Booked at 200 kr: the ceiling is 360 kr.
      ..bookedMaxOfferMinor = 36000;
    addTearDown(() => AppScope.instance.ride.bookedMaxOfferMinor = null);
    final controller = FindingDriverController(realtime: realtime, api: api);
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(375, 812),
        minTextAdapt: true,
        splitScreenMode: true,
        builder: (_, __) => MaterialApp(
          navigatorKey: nav,
          home: const Scaffold(body: Center(child: Text('research-home'))),
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

    realtime.assignNow();
    await pumpUntil(
      tester,
      () => find.byType(WaitingForDriver).evaluate().isNotEmpty,
    );
    expect(find.byType(WaitingForDriver), findsOneWidget);
    await pumpUntil(tester, () => false, max: 6);

    // A route change on Waiting is saved to the ride snapshot (and the
    // server) by RouteChangeController; Waiting itself pops only `true`.
    final stored = await RideSnapshotStore.read();
    expect(stored?.rideId, rideId);
    await RideSnapshotStore.save(
      stored!.copyWith(
        destinationAddress: 'Uppsala Central',
        destinationLat: 59.8586,
        destinationLng: 17.6389,
        price: 499,
        // The route change's new ceiling (1.8 x 300 kr on the server).
        maxOfferMinor: 54000,
        savedAt: DateTime.now(),
      ),
    );

    realtime.holdAssignment();
    realtime.cancelByDriver();
    await pumpUntil(
      tester,
      () =>
          find.byType(WaitingForDriver).evaluate().isEmpty &&
          controller.ownershipSnapshot?.destinationAddress == 'Uppsala Central',
    );

    expect(find.byType(WaitingForDriver), findsNothing);
    expect(find.byType(FindingDrivers), findsOneWidget);
    expect(controller.ownershipSnapshot?.destinationAddress, 'Uppsala Central');
    expect(controller.ownershipSnapshot?.destinationLat, 59.8586);
    expect(controller.currentPrice, 499);
    expect(controller.maxOfferPrice, 540);
    expect(AppScope.instance.ride.rideId, rideId);

    realtime.dispose();
    await tester.pump(driverCancelledNoticeDuration);
    await tester.pumpAndSettle();
  });
}
