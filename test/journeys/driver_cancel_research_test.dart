import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/router/routes.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/active_ride/presentation/driver_cancelled_notice.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    RideSnapshotStore.epoch = 0;
    AppScope.instance.ride
      ..rideId = null
      ..suppressRestore = false
      ..restoreFromBackend(RideStatus.idle);
  });

  testWidgets(
    'Waiting -> driver cancels -> search restarts by itself -> replacement driver',
    (tester) async {
      const rideId = 'journey-driver-research';
      final realtime = MockRideRealtime(assignAfter: const Duration(days: 1));
      addTearDown(realtime.dispose);

      realtime.subscribe(rideId);
      realtime.assignNow();
      await tester.pump(const Duration(milliseconds: 80));
      final firstDriver = realtime.lastDriver;
      expect(firstDriver, isNotNull);

      await RideSnapshotStore.save(
        RideSnapshot(
          status: RideStatus.driverAssigned,
          savedAt: DateTime.now(),
          pickupAddress: 'Stockholm pickup',
          destinationAddress: 'Stockholm destination',
          pickupLat: 59.3293,
          pickupLng: 18.0686,
          destinationLat: 59.3326,
          destinationLng: 18.0649,
          rideType: 'Movera',
          price: 259,
          paymentMethod: 'Apple Pay',
          rideId: rideId,
          driver: firstDriver,
        ),
      );
      AppScope.instance.ride.restoreFromBackend(
        RideStatus.driverAssigned,
        id: rideId,
      );

      final navKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navKey,
          home: const Scaffold(body: Text('finding-parent')),
        ),
      );

      navKey.currentState!.push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: AppRoutes.waitingForDriver),
          builder: (_) => WaitingForDriver(
            pickupAddress: 'Stockholm pickup',
            destinationAddress: 'Stockholm destination',
            pickupPosition: const LatLng(59.3293, 18.0686),
            destinationPosition: const LatLng(59.3326, 18.0649),
            rideType: 'Movera',
            price: 259,
            paymentMethod: 'Apple Pay',
            driver: firstDriver,
            realtime: realtime,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));

      expect(find.byType(WaitingForDriver), findsOneWidget);
      expect(
        ModalRoute.of(tester.element(find.byType(WaitingForDriver)))
            ?.settings
            .name,
        AppRoutes.waitingForDriver,
      );
      expect(AppScope.instance.ride.rideId, rideId);

      realtime.cancelByDriver();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));

      // Nothing to tap: the rider is told, and the search is already back.
      expect(find.text('Keep searching'), findsNothing);
      expect(find.byType(DriverCancelledNotice), findsWidgets);
      await tester.pumpAndSettle(const Duration(milliseconds: 350));
      // Once the search screen is back, the rider sees one notice on it.
      expect(find.text('${firstDriver!.firstName} cancelled'), findsOneWidget);
      expect(find.text(DriverCancelledNotice.body), findsOneWidget);

      expect(find.byType(WaitingForDriver), findsNothing);
      expect(find.text('finding-parent'), findsOneWidget);
      expect(AppScope.instance.ride.rideId, rideId);
      expect(AppScope.instance.ride.status, RideStatus.findingDriver);
      expect(realtime.lastStatus, RideStatus.findingDriver);

      // Keep the redispatch timer deterministic and trigger the next real
      // mock assignment ourselves.
      realtime.holdAssignment();
      realtime.assignNow();
      await tester.pump(const Duration(milliseconds: 100));

      expect(realtime.lastDriver, isNotNull);
      expect(realtime.lastDriver!.id, isNot(firstDriver.id));
      expect(AppScope.instance.ride.rideId, rideId);

      // The replacement assignment starts the real mock GPS cadence. Stop it
      // before Flutter verifies that the widget test has no orphan timers.
      realtime.dispose();
      await tester.pump(driverCancelledNoticeDuration);
      await tester.pumpAndSettle();
      expect(find.byType(DriverCancelledNotice), findsNothing);
    },
  );
}
