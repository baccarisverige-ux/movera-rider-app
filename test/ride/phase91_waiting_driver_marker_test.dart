import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/active_ride/presentation/driver_arrived_sheet.dart';
import 'package:movera_rider/features/active_ride/presentation/rider_in_trip_panel.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

RideSnapshot _snapshot(String rideId) => RideSnapshot(
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
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RideSnapshotStore.epoch = 0;
    AppScope.instance.ride
      ..rideId = null
      ..suppressRestore = false
      ..authoritativeVersion = null
      ..authoritativeUpdatedAt = null
      ..restoreFromBackend(RideStatus.idle);
  });

  Future<GlobalKey<NavigatorState>> pumpWaiting(
    WidgetTester tester, {
    required String rideId,
  }) async {
    await RideSnapshotStore.save(_snapshot(rideId));
    AppScope.instance.ride.restoreFromBackend(
      RideStatus.driverAssigned,
      id: rideId,
    );
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: Center(child: Text('audit-root'))),
      ),
    );
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const WaitingForDriver(
          pickupAddress: 'Stockholm pickup',
          destinationAddress: 'Stockholm destination',
          pickupPosition: LatLng(59.3293, 18.0686),
          destinationPosition: LatLng(59.3326, 18.0649),
          rideType: 'Movera',
          price: 259,
          paymentMethod: 'Apple Pay',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    return navigatorKey;
  }

  // R-037
  testWidgets(
    'the top-left button is always the cancel (X) icon, never the collapse chevron',
    (tester) async {
      await pumpWaiting(tester, rideId: 'phase91-icon');
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNothing);
      (AppScope.instance.rideRealtime as MockRideRealtime).holdAssignment();
    },
  );

  // R-038 / M-07
  testWidgets(
    'approachingDropoff is treated as in-trip: headline, panel copy and reference point all agree',
    (tester) async {
      await pumpWaiting(tester, rideId: 'phase91-approaching');
      final realtime = AppScope.instance.rideRealtime as MockRideRealtime;
      realtime.holdAssignment();
      // A real ride reaches approachingDropoff by progressing through every
      // intermediate stage, not by jumping straight there from
      // driverAssigned — the backend-reconcile state machine rejects
      // skipped stages as illegal/stale.
      for (final step in [
        RideStatus.driverArriving,
        RideStatus.driverWaiting,
        RideStatus.tripStarted,
        RideStatus.tripInProgress,
        RideStatus.approachingDropoff,
      ]) {
        realtime.emit(step, latitude: 59.331, longitude: 18.070);
        await tester.pump();
        if (step == RideStatus.driverWaiting) {
          // Reaching driverWaiting opens the driver-arrived sheet; give it
          // time to fully present before the next status pops it, matching
          // how this plays out for a real rider instead of racing frames.
          await tester.pump(const Duration(milliseconds: 400));
        }
      }
      await tester.pump(const Duration(milliseconds: 400));

      // approachingDropoff swaps in the in-trip panel: the chip says the
      // drop-off is near and the headline is the live arrival time.
      expect(find.byType(RiderInTripPanel), findsOneWidget);
      expect(find.text('NEAR DESTINATION'), findsOneWidget);
      expect(find.textContaining('Arrive by '), findsOneWidget);
      expect(find.textContaining('Stockholm destination'), findsWidgets);
      expect(find.textContaining('Meet at'), findsNothing);
    },
  );

  // R-039
  testWidgets(
    'a missing rideId shows an explicit retry/home state instead of silent inaction',
    (tester) async {
      AppScope.instance.ride
        ..rideId = null
        ..suppressRestore = false
        ..restoreFromBackend(RideStatus.idle);
      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: const Scaffold(body: Center(child: Text('audit-root'))),
        ),
      );
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const WaitingForDriver(
            pickupAddress: 'Stockholm pickup',
            destinationAddress: 'Stockholm destination',
            pickupPosition: LatLng(59.3293, 18.0686),
            destinationPosition: LatLng(59.3326, 18.0649),
            rideType: 'Movera',
            price: 259,
            paymentMethod: 'Apple Pay',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text("Can't track this ride"), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Go home'));
      await tester.pumpAndSettle();
      expect(find.text('audit-root'), findsOneWidget);
    },
  );

  // R-041
  testWidgets(
    'a cancel that fails restores state and shows an error instead of leaving the screen stuck',
    (tester) async {
      const rideId = 'phase91-cancel-fails';
      await RideSnapshotStore.save(_snapshot(rideId));
      AppScope.instance.ride.restoreFromBackend(
        RideStatus.driverAssigned,
        id: rideId,
      );
      final navigatorKey = GlobalKey<NavigatorState>();
      var attempts = 0;
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: const Scaffold(body: Center(child: Text('audit-root'))),
        ),
      );
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => WaitingForDriver(
            pickupAddress: 'Stockholm pickup',
            destinationAddress: 'Stockholm destination',
            pickupPosition: const LatLng(59.3293, 18.0686),
            destinationPosition: const LatLng(59.3326, 18.0649),
            rideType: 'Movera',
            price: 259,
            paymentMethod: 'Apple Pay',
            onCancel: (context, reasonId) async {
              attempts += 1;
              throw StateError('network down');
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      (AppScope.instance.rideRealtime as MockRideRealtime).holdAssignment();

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel request'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Driver/ride details are not suitable'));
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel ride'));
      await tester.pumpAndSettle();

      expect(attempts, 1);
      // Phase 142: the rider is told the scheduled ride is still booked.
      expect(
        find.text("Couldn't cancel. Your ride is still booked — try again."),
        findsOneWidget,
      );
      // Still on Waiting — the failure did not silently strand or advance it.
      expect(find.byType(WaitingForDriver), findsOneWidget);
      expect(find.text('audit-root'), findsNothing);
    },
  );

  // R-036
  testWidgets(
    'the driver-arrived sheet auto-dismisses once the trip actually starts',
    (tester) async {
      await pumpWaiting(tester, rideId: 'phase91-arrived-autodismiss');
      final realtime = AppScope.instance.rideRealtime as MockRideRealtime;
      realtime.holdAssignment();

      realtime.emit(
        RideStatus.driverWaiting,
        signal: RideRealtimeSignal.driverArrived,
        message: 'Your driver has arrived at the pickup point.',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(DriverArrivedSheet), findsOneWidget);

      realtime.emit(RideStatus.tripStarted);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(DriverArrivedSheet), findsNothing);
      // No driver fix has arrived in this test, so the stage name shows
      // until the live "Arrive by" time is known.
      expect(find.text('Ride in progress'), findsOneWidget);
    },
  );

  // M-09
  test('the mock moves the driver from pickup toward the destination during the trip', () async {
    final realtime =
        MockRideRealtime(
            assignAfter: const Duration(milliseconds: 1),
            boardAfter: const Duration(milliseconds: 1),
            tripTick: const Duration(milliseconds: 5),
            tripTicks: 4,
          )
          ..destinationLat = 59.35
          ..destinationLng = 18.10;
    addTearDown(realtime.dispose);

    final events = <RideRealtimeEvent>[];
    final sub = realtime.subscribe('m09-ride').listen(events.add);
    addTearDown(sub.cancel);
    // The normal assignment timer would otherwise race markArrivedForTest
    // and overwrite the trip it starts.
    realtime.holdAssignment();
    // markArrivedForTest is a test-only shortcut that skips the real
    // pre-trip GPS walk (which needs the mock API this test doesn't stand
    // up), so seed where the driver "was" at pickup for the trip to start
    // moving from.
    realtime.lastLat = 59.3293;
    realtime.lastLng = 18.0686;

    realtime.markArrivedForTest();
    // markArrivedForTest starts the trip immediately; wait until the last
    // tick has completed the trip (a fixed wait flaked under load).
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!events.any((e) => e.status == RideStatus.tripCompleted) &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    final tripCompleted = events
        .where((e) => e.status == RideStatus.tripCompleted)
        .firstOrNull;
    expect(tripCompleted, isNotNull);
    expect(tripCompleted!.latitude, isNotNull);
    expect(tripCompleted.longitude, isNotNull);
    // Landed at (or essentially at) the destination, not still at pickup.
    expect(tripCompleted.latitude, closeTo(59.35, 0.001));
    expect(tripCompleted.longitude, closeTo(18.10, 0.001));
  });
}
