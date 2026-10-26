import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/router/home_history_observer.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/active_ride/application/active_ride_controller.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/active_ride/presentation/driver_arrived_sheet.dart';
import 'package:movera_rider/features/active_ride/presentation/driver_cancelled_notice.dart';
import 'package:movera_rider/features/active_ride/presentation/ride_terminal_state_sheet.dart';
import 'package:movera_rider/features/finding_driver/presentation/finding_drivers.dart';
import 'package:movera_rider/features/history/data/on_demand_ride_history_store.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/shared/widgets/custom_google_map.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      ..restoreFromBackend(RideStatus.idle);
  });

  RideSnapshot waitingSnapshot(String rideId) => RideSnapshot(
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

  Future<void> expectWaitingLeavesOn(
    WidgetTester tester,
    RideStatus terminal,
  ) async {
    final rideId = 'waiting-${terminal.name}';
    final snapshot = waitingSnapshot(rideId);
    await RideSnapshotStore.save(snapshot);
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
    expect(find.byType(WaitingForDriver), findsOneWidget);

    final realtime = AppScope.instance.rideRealtime as MockRideRealtime;
    realtime.emit(terminal);
    await tester.pump();
    // Let the modal sheet finish its entrance before hit-testing the CTA.
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byType(RideTerminalStateSheet), findsOneWidget);
    expect(AppScope.instance.ride.status, terminal);
    expect(await RideSnapshotStore.read(), isNull);

    final acknowledge = find.byKey(
      const ValueKey<String>('ride-terminal-acknowledge'),
    );
    await tester.ensureVisible(acknowledge);
    await tester.pump();
    await tester.tap(acknowledge);
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    expect(find.byType(RideTerminalStateSheet), findsNothing);
    expect(find.byType(WaitingForDriver), findsNothing);
    expect(find.text('audit-root'), findsOneWidget);
    expect(AppScope.instance.ride.status, terminal);
  }

  // A driver dropping the ride before pickup is not the rider's ride ending:
  // dispatch looks again, so Waiting goes back to searching rather than Home,
  // and the ride is not filed away as cancelled.
  testWidgets(
    'driver cancellation reverses Waiting to its existing parent route',
    (tester) async {
      const rideId = 'waiting-driver-cancel-research';
      final snapshot = waitingSnapshot(rideId);
      await RideSnapshotStore.save(snapshot);
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
      expect(find.byType(WaitingForDriver), findsOneWidget);

      (AppScope.instance.rideRealtime as MockRideRealtime).emit(
        RideStatus.cancelledByDriver,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // The rider is told what happened, and is not asked anything.
      expect(find.byType(DriverCancelledNotice), findsWidgets);
      expect(find.text('Keep searching'), findsNothing);
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      expect(find.text('Your driver cancelled'), findsOneWidget);

      // Normal navigation reverses one level instead of stacking a second
      // Finding route. This isolated host uses audit-root as the parent; in the
      // production stack that parent is the already parked Finding route.
      expect(find.byType(WaitingForDriver), findsNothing);
      expect(find.text('audit-root'), findsOneWidget);
      expect(find.byType(FindingDrivers), findsNothing);
      expect(navigatorKey.currentState!.canPop(), isFalse);

      // The ride is still theirs: nothing archived, nothing wiped.
      expect(await OnDemandRideHistoryStore.read(), isEmpty);
      final realtime = AppScope.instance.rideRealtime as MockRideRealtime;
      expect(realtime.lastStatus, RideStatus.findingDriver);
      expect(AppScope.instance.ride.status, RideStatus.findingDriver);
      // researchAfterDriverCancel intentionally starts the next assignment timer.
      // This test only certifies the reverse route topology, so stop that future
      // mock assignment before Flutter verifies there are no leaked timers.
      realtime.holdAssignment();
      await tester.pump(driverCancelledNoticeDuration);
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'driver-arrived popup waits until a child route returns to the active ride',
    (tester) async {
      const rideId = 'waiting-arrival-child-route';
      await RideSnapshotStore.save(waitingSnapshot(rideId));
      AppScope.instance.ride.restoreFromBackend(
        RideStatus.driverAssigned,
        id: rideId,
      );

      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          navigatorObservers: [HomeHistoryObserver()],
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

      final realtime = AppScope.instance.rideRealtime as MockRideRealtime;
      realtime.holdAssignment();

      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) =>
              const Scaffold(body: Center(child: Text('temporary-child'))),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('temporary-child'), findsOneWidget);

      realtime.emit(
        RideStatus.driverWaiting,
        signal: RideRealtimeSignal.driverArrived,
        message: 'Driver arrived',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(find.byType(DriverArrivedSheet), findsNothing);
      expect(find.text('temporary-child'), findsOneWidget);

      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle(const Duration(milliseconds: 250));

      expect(find.byType(DriverArrivedSheet), findsOneWidget);

      // Close the modal and stop any future mock assignment before teardown.
      Navigator.of(
        tester.element(find.byType(DriverArrivedSheet)),
        rootNavigator: true,
      ).pop();
      await tester.pumpAndSettle();
      realtime.holdAssignment();
    },
  );

  testWidgets('system cancellation exits Waiting to Home exactly as terminal', (
    tester,
  ) async {
    await expectWaitingLeavesOn(tester, RideStatus.cancelledBySystem);
  });

  test(
    'external terminal cleanup never rewrites status as rider cancellation',
    () async {
      final snapshot = waitingSnapshot('waiting-controller-terminal');
      await RideSnapshotStore.save(snapshot);
      AppScope.instance.ride.restoreFromBackend(
        RideStatus.driverAssigned,
        id: snapshot.rideId,
      );

      await ActiveRideController().markExternalTerminal(
        RideStatus.cancelledByDriver,
      );

      expect(AppScope.instance.ride.status, RideStatus.cancelledByDriver);
      expect(await RideSnapshotStore.read(), isNull);
    },
  );

  test(
    'external terminal cleanup rejects non-external terminal inputs',
    () async {
      for (final status in <RideStatus>[
        RideStatus.driverAssigned,
        RideStatus.tripCompleted,
        RideStatus.cancelledByRider,
        RideStatus.closed,
      ]) {
        await expectLater(
          ActiveRideController().markExternalTerminal(status),
          throwsA(isA<ArgumentError>()),
          reason: status.name,
        );
      }
    },
  );

  testWidgets(
    'waiting stages keep the same map, panel and ride State mounted',
    (tester) async {
      const rideId = 'waiting-stage-continuity';
      await RideSnapshotStore.save(waitingSnapshot(rideId));
      AppScope.instance.ride.restoreFromBackend(
        RideStatus.driverAssigned,
        id: rideId,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: WaitingForDriver(
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

      final realtime = AppScope.instance.rideRealtime as MockRideRealtime;
      realtime.holdAssignment();
      final rideState = tester.state(find.byType(WaitingForDriver));
      final mapElement = tester.element(
        find.byKey(const ValueKey('waiting-map')),
      );
      final panelElement = tester.element(
        find.byKey(const ValueKey<String>('waiting-panel')),
      );

      expect(find.byType(WaitingForDriver), findsOneWidget);
      expect(find.byType(CustomGoogleMap), findsOneWidget);

      realtime.emit(
        RideStatus.driverArriving,
        latitude: 59.3310,
        longitude: 18.0600,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(WaitingForDriver), findsOneWidget);
      expect(
        identical(rideState, tester.state(find.byType(WaitingForDriver))),
        isTrue,
      );
      expect(
        identical(
          mapElement,
          tester.element(find.byKey(const ValueKey('waiting-map'))),
        ),
        isTrue,
      );
      expect(
        identical(
          panelElement,
          tester.element(find.byKey(const ValueKey<String>('waiting-panel'))),
        ),
        isTrue,
      );

      realtime.emit(
        RideStatus.driverWaiting,
        latitude: 59.3293,
        longitude: 18.0686,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Driver has arrived'), findsWidgets);
      expect(find.byType(WaitingForDriver), findsOneWidget);
      expect(
        identical(rideState, tester.state(find.byType(WaitingForDriver))),
        isTrue,
      );
      expect(
        identical(
          mapElement,
          tester.element(find.byKey(const ValueKey('waiting-map'))),
        ),
        isTrue,
      );
      expect(
        identical(
          panelElement,
          tester.element(find.byKey(const ValueKey<String>('waiting-panel'))),
        ),
        isTrue,
      );

      realtime.emit(RideStatus.tripStarted);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      realtime.emit(RideStatus.tripInProgress);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.textContaining('Arrive by '), findsOneWidget);
      expect(find.byType(WaitingForDriver), findsOneWidget);
      expect(
        identical(rideState, tester.state(find.byType(WaitingForDriver))),
        isTrue,
      );
      expect(
        identical(
          mapElement,
          tester.element(find.byKey(const ValueKey('waiting-map'))),
        ),
        isTrue,
      );
      expect(
        identical(
          panelElement,
          tester.element(find.byKey(const ValueKey<String>('waiting-panel'))),
        ),
        isTrue,
      );
    },
  );
}
