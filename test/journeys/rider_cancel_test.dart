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
import 'package:movera_rider/features/active_ride/application/active_ride_controller.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/presentation/finding_drivers.dart';
import 'package:movera_rider/features/history/data/on_demand_ride_history_store.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // rider-u235: one in-process backend per test, seeded with the ride, so a
  // cancel only passes when the server row really becomes cancelled (an
  // unseeded mock answers 404, which the cancel paths treat as confirmed).
  late InProcessMockClient server;

  /// The in-process backend without the platform token store, which never
  /// answers inside widget tests.
  ApiClient api() => ApiClient(client: server);

  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    server = InProcessMockClient();
    RideSnapshotStore.epoch = 0;
    FindingDriverController.active = null;
    AppScope.instance.ride
      ..rideId = null
      ..suppressRestore = false
      ..restoreFromBackend(RideStatus.idle);
  });

  Future<void> seed(String id, RideStatus status, String serverStatus) async {
    server.rides[id] = {'id': id, 'status': serverStatus};
    AppScope.instance.ride.restoreFromBackend(status, id: id);
    await RideSnapshotStore.save(
      RideSnapshot(
        status: status,
        savedAt: DateTime.now(),
        pickupAddress: 'Sveavägen 1',
        destinationAddress: 'Hornsgatan 2',
        pickupLat: 59.34,
        pickupLng: 18.05,
        destinationLat: 59.31,
        destinationLng: 18.04,
        rideType: 'Movera',
        price: 259,
        paymentMethod: 'Apple Pay',
        rideId: id,
      ),
    );
  }

  testWidgets('rider cancels while still searching', (tester) async {
    // Drives the real Finding screen: Cancel request commits the cancel
    // first, and the why-sheet afterwards is feedback only (CODE-3).
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const rideId = 'journey-cancel-searching';
    await seed(rideId, RideStatus.findingDriver, 'searching');
    final realtime = MockRideRealtime(assignAfter: const Duration(days: 1));
    addTearDown(realtime.dispose);
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => MaterialApp(
          navigatorKey: nav,
          home: const Scaffold(body: Text('journey-home')),
        ),
      ),
    );
    nav.currentState!.push(
      RideStageTransition(
        FindingDrivers(
          pickupAddress: 'Sveavägen 1',
          destinationAddress: 'Hornsgatan 2',
          pickupPosition: const LatLng(59.34, 18.05),
          destinationPosition: const LatLng(59.31, 18.04),
          rideType: 'Movera',
          price: 259,
          paymentMethod: 'Apple Pay',
          realtime: realtime,
          controller: FindingDriverController(realtime: realtime, api: api()),
        ),
        settings: const RouteSettings(name: AppRoutes.findingDriver),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(FindingDrivers), findsOneWidget);
    expect(AppScope.instance.ride.rideId, rideId);
    expect(AppScope.instance.ride.status, RideStatus.findingDriver);
    expect(await RideSnapshotStore.read(), isNotNull);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.widgetWithText(TextButton, 'Cancel request'));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('Plans changed').evaluate().isNotEmpty) break;
    }
    await tester.pump(const Duration(milliseconds: 400));

    // Committed before the reason is asked for.
    expect(AppScope.instance.ride.status, RideStatus.cancelledByRider);
    expect(await RideSnapshotStore.read(), isNull);
    expect(find.text('Keep ride'), findsNothing);

    await tester.tap(find.text('Plans changed'));
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Send'));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byType(FindingDrivers).evaluate().isEmpty) break;
    }
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(FindingDrivers), findsNothing);
    expect(AppScope.instance.ride.rideId, rideId);
    expect(AppScope.instance.ride.status, RideStatus.cancelledByRider);
    expect(await RideSnapshotStore.read(), isNull);
    expect(server.rides[rideId]!['status'], 'cancelled_by_rider');
  });

  testWidgets('rider cancels after driver assignment', (tester) async {
    // Drives the real Waiting screen (WaitingForDriver._confirmCancel) on a
    // server that holds the accepted trip.
    const rideId = 'journey-cancel-matched';
    await seed(rideId, RideStatus.driverAssigned, 'accepted');
    // Resumes at the matched stage, as a restore of this ride does.
    final realtime = MockRideRealtime(assignAfter: const Duration(days: 1))
      ..primeResume(status: RideStatus.driverAssigned);
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        home: const Scaffold(body: Text('journey-home')),
      ),
    );
    nav.currentState!.push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: AppRoutes.waitingForDriver),
        builder: (_) => WaitingForDriver(
          pickupAddress: 'Sveavägen 1',
          destinationAddress: 'Hornsgatan 2',
          pickupPosition: const LatLng(59.34, 18.05),
          destinationPosition: const LatLng(59.31, 18.04),
          rideType: 'Movera',
          price: 259,
          paymentMethod: 'Apple Pay',
          rideId: rideId,
          realtime: realtime,
          controller: ActiveRideController(api: api()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(WaitingForDriver), findsOneWidget);
    expect(AppScope.instance.ride.status, RideStatus.driverAssigned);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel request'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Driver/ride details are not suitable'));
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel ride'));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byType(WaitingForDriver).evaluate().isEmpty) break;
    }
    await tester.pumpAndSettle();

    expect(server.rides[rideId]!['status'], 'cancelled_by_rider');
    expect(find.byType(WaitingForDriver), findsNothing);
    expect(find.text('journey-home'), findsOneWidget);
    expect(AppScope.instance.ride.rideId, rideId);
    expect(AppScope.instance.ride.status, RideStatus.cancelledByRider);
    expect(await RideSnapshotStore.read(), isNull);
    final history = await OnDemandRideHistoryStore.read();
    expect(history.single.reservationId, 'ondemand-$rideId');
    realtime.dispose();
    await tester.pump(const Duration(seconds: 1));
  });
}
