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

  // Audit 2026-10-21 (rider-27): a driver drop while a page is open on top of
  // Waiting must leave Waiting itself and restart the search, not just close
  // that page and strand a dead Waiting screen.
  testWidgets('driver drop with a page open on Waiting goes back to the search',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const rideId = 'research-child-page';
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
    await pumpUntil(tester, () => false, max: 6);

    // The rider opens a page from Waiting (driver profile, chat, ...).
    Navigator.of(tester.element(find.byType(WaitingForDriver))).push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('child page')),
      ),
    );
    await pumpUntil(tester, () => false, max: 10);
    expect(find.text('child page'), findsOneWidget);

    // Waiting is still mounted under the page, so look offstage too.
    final waiting = find.byType(WaitingForDriver, skipOffstage: false);
    realtime.holdAssignment();
    realtime.cancelByDriver();
    await pumpUntil(tester, () => waiting.evaluate().isEmpty);
    // Let the closing page finish its exit transition.
    await pumpUntil(tester, () => false, max: 20);

    expect(find.text('child page', skipOffstage: false), findsNothing);
    expect(waiting, findsNothing);
    expect(find.byType(FindingDrivers), findsOneWidget);
    expect(FindingDriverController.active, isNotNull);
    expect(AppScope.instance.ride.rideId, rideId);

    realtime.dispose();
    await tester.pump(driverCancelledNoticeDuration);
    await tester.pumpAndSettle();
  });
}
