import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/active_ride/application/active_ride_controller.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/history/application/on_demand_history_controller.dart';
import 'package:movera_rider/features/history/data/on_demand_ride_history_store.dart';
import 'package:movera_rider/features/history/presentation/ride_history.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RideSnapshotStore.epoch = 0;
    FindingDriverController.active = null;
    AppScope.instance.ride
      ..rideId = null
      ..status = RideStatus.idle;
  });

  RideSnapshot snapshot({
    String? rideId = 'ride-1',
    RideStatus status = RideStatus.tripInProgress,
    double price = 259,
    DateTime? savedAt,
    String destination = 'Stockholm Central Station',
  }) {
    return RideSnapshot(
      status: status,
      savedAt: savedAt ?? DateTime.now().subtract(const Duration(minutes: 12)),
      pickupAddress: 'Current location',
      destinationAddress: destination,
      pickupLat: 59.3293,
      pickupLng: 18.0686,
      destinationLat: 59.3301,
      destinationLng: 18.058,
      rideType: 'Movera',
      price: price,
      paymentMethod: 'Apple Pay',
      rideId: rideId,
    );
  }

  Reservation historyRide({
    required String id,
    required ReservationStatus status,
    required DateTime endedAt,
    required String destination,
  }) {
    return Reservation(
      reservationId: id,
      createdAt: endedAt.subtract(const Duration(minutes: 20)),
      scheduledPickupAt: endedAt,
      pickup: const ReservationPlace(label: 'Pickup'),
      destination: ReservationPlace(label: destination),
      categoryId: 'economy',
      categoryName: 'Movera',
      categoryImage: 'assets/images/rides/movera.webp',
      price: 259,
      paymentMethod: 'Apple Pay',
      status: status,
    );
  }

  ReservationController emptyReservations() {
    return ReservationController(
      store: LocalReservationRepository(storage: MemoryReservationStorage()),
    );
  }

  test('fresh install has honest empty on-demand History', () async {
    expect(await OnDemandRideHistoryStore.read(), isEmpty);
    expect(await const OnDemandHistoryController().load(), isEmpty);
  });

  test(
    'completed Book Now ride archives while completion snapshot stays restorable',
    () async {
      final active = snapshot(
        rideId: 'ride-completed',
        savedAt: DateTime.now().subtract(const Duration(minutes: 45)),
      );
      await RideSnapshotStore.save(active);
      expect(
        await RideSnapshotStore.read(),
        isNotNull,
        reason:
            'a 45-minute trip in progress is a real ride, not a stale '
            'search, so it still resumes',
      );
      AppScope.instance.ride
        ..rideId = 'ride-completed'
        ..status = RideStatus.tripInProgress;

      await ActiveRideController().markCompleted(RideStatus.tripCompleted);

      final history = await OnDemandRideHistoryStore.read();
      expect(history, hasLength(1));
      expect(history.single.reservationId, 'ondemand-ride-completed');
      expect(history.single.status, ReservationStatus.completed);
      expect(history.single.pickup.label, 'Current location');
      expect(history.single.destination.label, 'Stockholm Central Station');
      expect(history.single.price, 259);
      final completionSnapshot = await RideSnapshotStore.readForArchive();
      expect(completionSnapshot, isNotNull);
      expect(completionSnapshot!.status, RideStatus.tripCompleted);
      expect(completionSnapshot.rideId, 'ride-completed');
      expect(AppScope.instance.ride.status, RideStatus.tripCompleted);
    },
  );

  test('cancelled Book Now ride is archived with its reason', () async {
    final active = snapshot(rideId: 'ride-cancelled');
    await RideSnapshotStore.save(active);
    AppScope.instance.ride
      ..rideId = 'ride-cancelled'
      ..status = RideStatus.driverAssigned;

    await ActiveRideController().markCancelled(reasonId: 'changed-plans');

    final history = await OnDemandRideHistoryStore.read();
    expect(history, hasLength(1));
    expect(history.single.reservationId, 'ondemand-ride-cancelled');
    expect(history.single.status, ReservationStatus.cancelled);
    expect(history.single.cancellationReason, 'changed-plans');
    expect(await RideSnapshotStore.readForArchive(), isNull);
  });

  test('archive deduplicates retries using the real rideId', () async {
    final ride = snapshot(rideId: 'ride-retry');
    final firstEnd = DateTime.now().subtract(const Duration(minutes: 2));
    final secondEnd = DateTime.now().subtract(const Duration(minutes: 1));

    await OnDemandRideHistoryStore.archive(
      ride,
      terminalStatus: RideStatus.tripCompleted,
      endedAt: firstEnd,
    );
    await OnDemandRideHistoryStore.archive(
      ride,
      terminalStatus: RideStatus.paymentFinalized,
      endedAt: secondEnd,
    );

    final history = await OnDemandRideHistoryStore.read();
    expect(history, hasLength(1));
    expect(history.single.reservationId, 'ondemand-ride-retry');
    // Persistence is UTC; History reads it back in local time (rider-36).
    expect(history.single.scheduledPickupAt, secondEnd);
  });

  test('archive refuses to invent an id when rideId is missing', () async {
    await expectLater(
      OnDemandRideHistoryStore.archive(
        snapshot(rideId: null),
        terminalStatus: RideStatus.tripCompleted,
      ),
      throwsA(isA<ArgumentError>()),
    );
    expect(await OnDemandRideHistoryStore.read(), isEmpty);
  });

  test('only completed, cancelled or server-ended searches archive', () async {
    // rider-37: a payment-failed trip is now a completed History ride, so a
    // live trip stands in for the status History refuses.
    await expectLater(
      OnDemandRideHistoryStore.archive(
        snapshot(rideId: 'ride-in-progress'),
        terminalStatus: RideStatus.tripInProgress,
      ),
      throwsA(isA<ArgumentError>()),
    );
    expect(await OnDemandRideHistoryStore.read(), isEmpty);

    // ARCH-3 / RIDE-5: a search the server ended is kept as a cancelled
    // attempt, with the reason the rider saw.
    await OnDemandRideHistoryStore.archive(
      snapshot(rideId: 'ride-no-driver'),
      terminalStatus: RideStatus.noDriverFound,
    );
    final history = await OnDemandRideHistoryStore.read();
    expect(history.single.reservationId, 'ondemand-ride-no-driver');
    expect(history.single.status.name, 'cancelled');
    expect(history.single.cancellationReason, 'system_no_driver');
  });

  test('multiple archived rides are newest first', () async {
    final older = DateTime.now().subtract(const Duration(minutes: 5));
    final newer = DateTime.now().subtract(const Duration(minutes: 1));
    await OnDemandRideHistoryStore.archive(
      snapshot(rideId: 'ride-old', destination: 'Old destination'),
      terminalStatus: RideStatus.tripCompleted,
      endedAt: older,
    );
    await OnDemandRideHistoryStore.archive(
      snapshot(rideId: 'ride-new', destination: 'New destination'),
      terminalStatus: RideStatus.tripCompleted,
      endedAt: newer,
    );

    final history = await OnDemandRideHistoryStore.read();
    expect(history.map((ride) => ride.reservationId), [
      'ondemand-ride-new',
      'ondemand-ride-old',
    ]);
  });

  test('History survives a new controller load like app restart', () async {
    await OnDemandRideHistoryStore.archive(
      snapshot(rideId: 'ride-restart'),
      terminalStatus: RideStatus.tripCompleted,
    );

    final afterRestart = await const OnDemandHistoryController().load();
    expect(afterRestart, hasLength(1));
    expect(afterRestart.single.reservationId, 'ondemand-ride-restart');
  });

  test('scheduled and Book Now History merge by terminal date', () {
    final controller = const OnDemandHistoryController();
    final now = DateTime.now();
    final scheduled = historyRide(
      id: 'scheduled-1',
      status: ReservationStatus.completed,
      endedAt: now.subtract(const Duration(minutes: 4)),
      destination: 'Scheduled destination',
    );
    final onDemand = historyRide(
      id: 'ondemand-ride-2',
      status: ReservationStatus.completed,
      endedAt: now.subtract(const Duration(minutes: 1)),
      destination: 'Book Now destination',
    );
    final cancelled = historyRide(
      id: 'ondemand-cancelled',
      status: ReservationStatus.cancelled,
      endedAt: now,
      destination: 'Cancelled destination',
    );

    final completed = controller.combine(
      [scheduled],
      [onDemand, cancelled],
      completed: true,
    );
    expect(completed.map((ride) => ride.reservationId), [
      'ondemand-ride-2',
      'scheduled-1',
    ]);

    final cancelledOnly = controller.combine(const [], [
      onDemand,
      cancelled,
    ], completed: false);
    expect(cancelledOnly.map((ride) => ride.reservationId), [
      'ondemand-cancelled',
    ]);
  });

  testWidgets('Book Now record appears only in its real History tab', (
    tester,
  ) async {
    final ride = historyRide(
      id: 'ondemand-widget',
      status: ReservationStatus.completed,
      endedAt: DateTime.now(),
      destination: 'Book Now destination',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: RideHistory(
          reservations: emptyReservations(),
          onDemandReader: () async => [ride],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Completed'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Book Now destination'), findsOneWidget);
    expect(find.text('No cancelled rides'), findsNothing);

    await tester.tap(find.text('Cancelled'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Book Now destination'), findsNothing);
    expect(find.text('No cancelled rides'), findsOneWidget);
  });

  test(
    'Finding cancelSearch archives History then clears the snapshot',
    () async {
      final active = snapshot(
        rideId: 'ride-search-cancel',
        status: RideStatus.findingDriver,
      );
      await RideSnapshotStore.save(active);
      AppScope.instance.ride
        ..rideId = 'ride-search-cancel'
        ..status = RideStatus.findingDriver;
      final rt = MockRideRealtime(assignAfter: const Duration(days: 1));
      final controller = FindingDriverController(
        realtime: rt,
        ride: AppScope.instance.ride,
      );
      controller.start(snapshot: active, onTick: (_) {}, onMatched: () {});
      await controller.cancelSearch(reasonId: 'wait_too_long');

      final history = await OnDemandRideHistoryStore.read();
      expect(history, hasLength(1));
      expect(history.single.reservationId, 'ondemand-ride-search-cancel');
      expect(history.single.status, ReservationStatus.cancelled);
      expect(history.single.cancellationReason, 'wait_too_long');
      expect(await RideSnapshotStore.readForArchive(), isNull);
      controller.dispose();
      rt.dispose();
    },
  );

  test('Waiting cancel archives when Finding UI is not mounted', () async {
    final active = snapshot(rideId: 'ride-waiting-cancel');
    await RideSnapshotStore.save(active);
    AppScope.instance.ride
      ..rideId = 'ride-waiting-cancel'
      ..status = RideStatus.driverAssigned;
    FindingDriverController.active = null;

    await ActiveRideController().markCancelled(reasonId: 'changed-plans');

    final history = await OnDemandRideHistoryStore.read();
    expect(history, hasLength(1));
    expect(history.single.reservationId, 'ondemand-ride-waiting-cancel');
    expect(history.single.status, ReservationStatus.cancelled);
    expect(history.single.cancellationReason, 'changed-plans');
    expect(await RideSnapshotStore.readForArchive(), isNull);
    expect(AppScope.instance.ride.status, RideStatus.cancelledByRider);
  });

  test('a repeated Waiting cancel does not duplicate History', () async {
    final active = snapshot(rideId: 'ride-waiting-archive-once');
    await RideSnapshotStore.save(active);
    AppScope.instance.ride
      ..rideId = 'ride-waiting-archive-once'
      ..status = RideStatus.driverAssigned;
    FindingDriverController.active = null;

    await ActiveRideController().markCancelled();
    await ActiveRideController().markCancelled(reasonId: 'changed-plans');

    final history = await OnDemandRideHistoryStore.read();
    expect(history, hasLength(1));
    expect(history.single.reservationId, 'ondemand-ride-waiting-archive-once');
  });
}
