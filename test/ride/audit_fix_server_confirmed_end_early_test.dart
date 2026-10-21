import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/active_ride/application/active_ride_controller.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/history/data/on_demand_ride_history_store.dart';
import 'package:movera_rider/features/reservations/presentation/reservation_format.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_complete/data/last_completed_ride.dart';
import 'package:movera_rider/features/ride_complete/presentation/ride_completed.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// rider-u51: an on-board "End trip" that could not reach the server waits
/// in the outbox; when it is delivered later the server moves the trip to
/// cancelled_by_rider (the contract's end_early outcome) and realtime
/// reports that to Waiting. Waiting committed it as a plain cancel: no
/// ended-early summary, no rating, History "Cancelled" with no charge.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  RideSnapshot snapshot(String rideId, RideStatus status) => RideSnapshot(
    status: status,
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

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RideSnapshotStore.epoch = 0;
    LastCompletedRide.clear();
    AppScope.instance.ride
      ..rideId = null
      ..suppressRestore = false
      ..authoritativeVersion = null
      ..authoritativeUpdatedAt = null
      ..restoreFromBackend(RideStatus.idle);
  });

  testWidgets(
    'a server-confirmed end-early opens the ended-early summary, not Home',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const rideId = 'waiting-queued-end-early';
      await RideSnapshotStore.save(snapshot(rideId, RideStatus.tripInProgress));
      // As a restore seeds it: the stored trip's server version, so the
      // mock transport's opening event does not move the stage back.
      AppScope.instance.ride
        ..restoreFromBackend(RideStatus.tripInProgress, id: rideId)
        ..authoritativeVersion = 1;

      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(375, 812),
          builder: (_, __) => MaterialApp(
            navigatorKey: navigatorKey,
            home: const Scaffold(body: Center(child: Text('audit-root'))),
          ),
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

      // The queued end-early landed: the server closed the trip as
      // cancelled_by_rider and realtime reports it.
      final realtime = AppScope.instance.rideRealtime as MockRideRealtime;
      realtime.emit(RideStatus.cancelledByRider);
      await tester.pump();
      await tester.pumpAndSettle(const Duration(milliseconds: 600));

      expect(tester.takeException(), isNull);
      expect(find.byType(WaitingForDriver), findsNothing);
      // UI-01: a finished trip with a receipt and a rating (R-O6).
      expect(find.byType(RideCompleted), findsOneWidget);
      expect(find.text('Trip ended early'), findsOneWidget);
      expect(find.byKey(const ValueKey('completion-feedback')), findsOneWidget);
      expect(find.text('audit-root'), findsNothing);

      expect(AppScope.instance.ride.status, RideStatus.cancelledByRider);
      expect(await RideSnapshotStore.read(), isNull);
      final record = (await OnDemandRideHistoryStore.read()).single;
      expect(record.endedEarly, isTrue);
      expect(ReservationFormat.historyStatus(record), 'Ended early');
    },
  );

  test(
    'the controller files an on-board server cancel as ended early',
    () async {
      const rideId = 'controller-queued-end-early';
      await RideSnapshotStore.save(
        snapshot(rideId, RideStatus.approachingDropoff),
      );
      AppScope.instance.ride.restoreFromBackend(
        RideStatus.cancelledByRider,
        id: rideId,
      );

      final controller = ActiveRideController();
      await controller.completeServerConfirmedCancel(drivenMeters: 3200);

      expect(controller.endedEarly?.rideId, rideId);
      expect(controller.endedEarly?.drivenMeters, 3200);
      expect(LastCompletedRide.endedEarly, isTrue);
      expect(LastCompletedRide.forRide(rideId), isNotNull);
      final record = (await OnDemandRideHistoryStore.read()).single;
      expect(record.endedEarly, isTrue);
    },
  );

  test('a server cancel before boarding stays a plain cancel', () async {
    const rideId = 'controller-queued-cancel';
    await RideSnapshotStore.save(snapshot(rideId, RideStatus.driverArriving));
    AppScope.instance.ride.restoreFromBackend(
      RideStatus.cancelledByRider,
      id: rideId,
    );

    final controller = ActiveRideController();
    await controller.completeServerConfirmedCancel();

    expect(controller.endedEarly, isNull);
    expect(LastCompletedRide.endedEarly, isFalse);
    final record = (await OnDemandRideHistoryStore.read()).single;
    expect(record.endedEarly, isFalse);
    expect(ReservationFormat.historyStatus(record), 'Cancelled');
  });
}
