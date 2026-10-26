import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/driver_arriving/application/driver_tracking_controller.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/application/reservation_ride_realtime.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';
import 'package:movera_rider/features/reservations/presentation/reservation_live_ride.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> flush() => Future<void>.delayed(const Duration(milliseconds: 10));

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    RideSnapshotStore.epoch = 0;
  });

  Future<(ReservationController, Reservation)> seeded({
    String id = 'scheduled-live-1',
  }) async {
    final controller = ReservationController(
      store: LocalReservationRepository(
        storage: MemoryReservationStorage(),
        nextId: () => id,
      ),
    );
    final ride = await controller.create(
      ReservationDraft(
        scheduledPickupAt: DateTime(2026, 9, 23, 8),
        pickup: const ReservationPlace(
          label: 'Stockholm Central',
          lat: 59.3300,
          lng: 18.0590,
        ),
        destination: const ReservationPlace(
          label: 'Arlanda Airport',
          lat: 59.6519,
          lng: 17.9186,
        ),
        categoryId: 'economy',
        categoryName: 'Movera',
        categoryImage: 'assets/images/rides/movera.webp',
        price: 349,
        paymentMethod: 'Apple Pay',
      ),
    );
    return (controller, ride);
  }

  const driverA = ReservationDriver(
    firstName: 'Amina',
    rating: 4.9,
    vehicle: 'Volvo EX40',
    plate: 'ABC 123',
  );

  const driverB = ReservationDriver(
    firstName: 'Nora',
    rating: 4.8,
    vehicle: 'Mercedes EQE',
    plate: 'XYZ 789',
  );

  test(
    'scheduled live page is wired to reservation id and transport',
    () async {
      final (controller, created) = await seeded();
      await controller.assignMockDriver(created.reservationId, driver: driverA);
      final live = await controller.update(
        created.reservationId,
        const ReservationPatch(status: ReservationStatus.driverEnRoute),
      );

      final page = ReservationLiveRide.pageFor(live, controller: controller);

      expect(page.rideId, live.reservationId);
      expect(page.realtime, isA<ReservationRideRealtime>());
      expect(page.persistRideSnapshot, isFalse);
      expect(page.onCancel, isNotNull);
      expect(page.onDriverCancelled, isNotNull);
      expect(page.onTerminal, isNotNull);
      expect(page.onCompleted, isNotNull);
    },
  );

  test(
    'scheduled realtime maps authoritative lifecycle without fake payment states',
    () async {
      final (controller, created) = await seeded(id: 'scheduled-map');
      await controller.assignMockDriver(created.reservationId, driver: driverA);
      await controller.update(
        created.reservationId,
        const ReservationPatch(status: ReservationStatus.driverEnRoute),
      );

      final realtime = ReservationRideRealtime(
        controller: controller,
        reservationId: created.reservationId,
      );
      addTearDown(realtime.dispose);
      expect(realtime.supportsRiderSignals, isFalse);

      final events = <RideStatus>[];
      final signals = <String>[];
      final sub = realtime.subscribe(created.reservationId).listen((event) {
        events.add(event.status);
        if (event.signal != null) signals.add(event.signal!.name);
      });
      addTearDown(sub.cancel);

      await flush();
      expect(events.last, RideStatus.driverArriving);

      await controller.update(
        created.reservationId,
        const ReservationPatch(status: ReservationStatus.driverArrived),
      );
      await flush();
      expect(events.last, RideStatus.driverWaiting);
      expect(signals, contains('driverArrived'));

      await controller.update(
        created.reservationId,
        const ReservationPatch(status: ReservationStatus.inProgress),
      );
      await flush();
      expect(events.last, RideStatus.tripInProgress);

      await controller.update(
        created.reservationId,
        const ReservationPatch(status: ReservationStatus.completed),
      );
      await flush();
      expect(events.last, RideStatus.tripCompleted);
      expect(
        events.where(
          (status) =>
              status == RideStatus.paymentProcessing ||
              status == RideStatus.paymentFinalized ||
              status == RideStatus.ratingPending,
        ),
        isEmpty,
        reason:
            'Reservation model has no authoritative payment/rating state yet.',
      );
    },
  );

  test(
    'scheduled driver cancel is transient and reassigns the same reservation',
    () async {
      final (controller, created) = await seeded(id: 'scheduled-reassign');
      await controller.assignMockDriver(created.reservationId, driver: driverA);
      await controller.update(
        created.reservationId,
        const ReservationPatch(status: ReservationStatus.driverEnRoute),
      );

      final realtime = ReservationRideRealtime(
        controller: controller,
        reservationId: created.reservationId,
      );
      addTearDown(realtime.dispose);

      final events = <RideStatus>[];
      final sub = realtime
          .subscribe(created.reservationId)
          .listen((event) => events.add(event.status));
      addTearDown(sub.cancel);
      await flush();

      final pending = await controller.driverCancelled(created.reservationId);
      await flush();

      expect(pending.reservationId, created.reservationId);
      expect(pending.status, ReservationStatus.driverAssignmentPending);
      expect(pending.driver, isNull);
      expect(events.last, RideStatus.cancelledByDriver);

      final reassigned = await controller.assignMockDriver(
        created.reservationId,
        driver: driverB,
      );
      await flush();
      expect(reassigned.reservationId, created.reservationId);
      expect(reassigned.status, ReservationStatus.driverAssigned);
      expect(events.last, RideStatus.driverAssigned);

      await controller.update(
        created.reservationId,
        const ReservationPatch(status: ReservationStatus.driverEnRoute),
      );
      await flush();
      expect(events.last, RideStatus.driverArriving);
    },
  );

  test(
    'authoritative assignment updates Rider without reload and replacement stays on same reservation',
    () async {
      final (controller, created) = await seeded(id: 'scheduled-authoritative');
      await controller.startLiveIfDue(
        now: created.scheduledPickupAt.subtract(const Duration(minutes: 1)),
      );

      final realtime = ReservationRideRealtime(
        controller: controller,
        reservationId: created.reservationId,
      );
      addTearDown(realtime.dispose);

      final events = <RideRealtimeEvent>[];
      final sub = realtime.subscribe(created.reservationId).listen(events.add);
      addTearDown(sub.cancel);
      await flush();
      expect(events.last.status, RideStatus.findingDriver);
      expect(events.last.driver, isNull);

      final assigned = await controller.applyDriverAssignment(
        created.reservationId,
        driver: driverA,
      );
      await flush();
      expect(assigned.reservationId, created.reservationId);
      expect(assigned.status, ReservationStatus.driverAssigned);
      expect(events.last.status, RideStatus.driverAssigned);
      expect(events.last.driver?.firstName, 'Amina');

      final pending = await controller.applyDriverCancellation(
        created.reservationId,
      );
      await flush();
      expect(pending.reservationId, created.reservationId);
      expect(pending.status, ReservationStatus.driverAssignmentPending);
      expect(pending.driver, isNull);
      expect(events.last.status, RideStatus.cancelledByDriver);
      expect(events.last.driver, isNull);

      final replacement = await controller.applyDriverAssignment(
        created.reservationId,
        driver: driverB,
      );
      await flush();
      expect(replacement.reservationId, created.reservationId);
      expect(replacement.status, ReservationStatus.driverAssigned);
      expect(events.last.status, RideStatus.driverAssigned);
      expect(events.last.driver?.firstName, 'Nora');
    },
  );

  test(
    'unsolicited scheduled cancellation is external, not invented rider action',
    () async {
      final (controller, created) = await seeded(
        id: 'scheduled-external-cancel',
      );
      await controller.assignMockDriver(created.reservationId, driver: driverA);
      await controller.update(
        created.reservationId,
        const ReservationPatch(status: ReservationStatus.driverEnRoute),
      );

      final realtime = ReservationRideRealtime(
        controller: controller,
        reservationId: created.reservationId,
      );
      addTearDown(realtime.dispose);

      RideStatus? last;
      final sub = realtime
          .subscribe(created.reservationId)
          .listen((event) => last = event.status);
      addTearDown(sub.cancel);
      await flush();

      await controller.cancel(created.reservationId, reason: 'external-test');
      await flush();

      expect(last, RideStatus.cancelledBySystem);
    },
  );

  test(
    'scheduled tracking cannot overwrite an on-demand restore snapshot',
    () async {
      final (controller, created) = await seeded(
        id: 'scheduled-snapshot-isolation',
      );
      await controller.assignMockDriver(created.reservationId, driver: driverA);
      await controller.update(
        created.reservationId,
        const ReservationPatch(status: ReservationStatus.driverEnRoute),
      );

      final original = RideSnapshot(
        status: RideStatus.findingDriver,
        savedAt: DateTime.now(),
        pickupAddress: 'Book Now pickup',
        destinationAddress: 'Book Now destination',
        pickupLat: 59.3,
        pickupLng: 18.0,
        destinationLat: 59.4,
        destinationLng: 18.1,
        rideType: 'Movera',
        price: 199,
        paymentMethod: 'Apple Pay',
        rideId: 'on-demand-stays-untouched',
      );
      await RideSnapshotStore.save(original);

      final realtime = ReservationRideRealtime(
        controller: controller,
        reservationId: created.reservationId,
      );
      final tracking = DriverTrackingController(
        realtime: realtime,
        pickupLat: 59.3300,
        pickupLng: 18.0590,
        persistRideSnapshot: false,
      );
      addTearDown(() {
        tracking.dispose();
        realtime.dispose();
      });

      tracking.start(rideId: created.reservationId);
      await flush();

      final after = await RideSnapshotStore.read();
      expect(after?.rideId, original.rideId);
      expect(after?.status, original.status);
      expect(after?.pickupAddress, original.pickupAddress);
    },
  );
}
