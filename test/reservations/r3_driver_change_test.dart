import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/data/mock_reservation_dispatch.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';

/// Round 3 Q12: the rider sees the driver as soon as one accepts, and sees
/// the new one when the driver changes. Q11: a late cancel keeps its fee.
void main() {
  const demo = AppEnv(
    flavor: AppFlavor.demo,
    apiBaseUrl: 'https://api.demo.movera.invalid',
  );
  final bookedAt = DateTime(2026, 10, 15, 9, 0);
  final pickupAt = DateTime(2026, 10, 16, 8, 0);

  const elin = ReservationDriver(
    firstName: 'Elin',
    id: 'drv_mock_001',
    vehicle: 'Volvo XC40 Recharge',
    plate: 'MVR 204',
  );
  const johan = ReservationDriver(
    firstName: 'Johan',
    id: 'drv_mock_002',
    vehicle: 'Volvo V60',
    plate: 'MVR 771',
  );

  ReservationDraft draft() => ReservationDraft(
    scheduledPickupAt: pickupAt,
    pickup: const ReservationPlace(label: 'Stockholm Central'),
    destination: const ReservationPlace(label: 'Arlanda Airport'),
    categoryId: 'economy',
    categoryName: 'Movera',
    categoryImage: 'assets/images/rides/movera.webp',
    price: 459,
    paymentMethod: 'Visa •••• 4242',
  );

  ReservationController controller({
    MemoryReservationStorage? storage,
    MockReservationDispatch? dispatch,
  }) {
    return ReservationController(
      store: LocalReservationRepository(
        storage: storage ?? MemoryReservationStorage(),
        nextId: () => 'rsv_r3',
        clock: () => bookedAt,
      ),
      environment: demo,
      mockDispatch: dispatch,
    );
  }

  group('repository keeps the driver who handed the ride over', () {
    test('a different driver records the previous one', () async {
      final c = controller();
      await c.create(draft());
      await c.applyDriverAssignment('rsv_r3', driver: elin);
      expect(c.byId('rsv_r3')!.driverChanged, isFalse);

      await c.applyDriverAssignment('rsv_r3', driver: johan);
      final ride = c.byId('rsv_r3')!;
      expect(ride.status, ReservationStatus.driverAssigned);
      expect(ride.driver!.firstName, 'Johan');
      expect(ride.previousDriver!.firstName, 'Elin');
      expect(ride.driverChanged, isTrue);
    });

    test('the same assignment again is not a change', () async {
      final c = controller();
      await c.create(draft());
      await c.applyDriverAssignment('rsv_r3', driver: elin);
      await c.applyDriverAssignment('rsv_r3', driver: elin);
      expect(c.byId('rsv_r3')!.previousDriver, isNull);
      expect(c.byId('rsv_r3')!.driverChanged, isFalse);
    });

    test('a driver drop keeps who left, then the next driver is new', () async {
      final c = controller();
      await c.create(draft());
      await c.applyDriverAssignment('rsv_r3', driver: elin);
      await c.applyDriverCancellation('rsv_r3');
      var ride = c.byId('rsv_r3')!;
      expect(ride.status, ReservationStatus.driverAssignmentPending);
      expect(ride.driver, isNull);
      expect(ride.previousDriver!.firstName, 'Elin');
      expect(ride.driverChanged, isFalse);

      await c.applyDriverAssignment('rsv_r3', driver: johan);
      ride = c.byId('rsv_r3')!;
      expect(ride.driverChanged, isTrue);
      expect(ride.previousDriver!.firstName, 'Elin');
    });

    test(
      'driver id, car colour, previous driver and fee survive a restart',
      () async {
        final storage = MemoryReservationStorage();
        final before = controller(storage: storage);
        await before.create(draft());
        await before.applyDriverAssignment(
          'rsv_r3',
          driver: const ReservationDriver(
            firstName: 'Elin',
            id: 'drv_mock_001',
            vehicle: 'Volvo XC40 Recharge',
            vehicleColor: 'Black',
            plate: 'MVR 204',
            photoAsset: 'assets/images/driver_img.webp',
          ),
        );
        await before.applyDriverAssignment('rsv_r3', driver: johan);
        await before.cancel(
          'rsv_r3',
          reason: 'plans_changed',
          fee: const Money(5000),
        );

        final after = controller(storage: storage);
        await after.hydrate();
        final ride = after.byId('rsv_r3')!;
        expect(ride.status, ReservationStatus.cancelled);
        expect(ride.cancellationFee, const Money(5000));
        expect(ride.previousDriver!.id, 'drv_mock_001');
        expect(ride.previousDriver!.carLabel, 'Black Volvo XC40 Recharge');
        expect(
          ride.previousDriver!.photoAsset,
          'assets/images/driver_img.webp',
        );
        expect(ride.driver!.id, 'drv_mock_002');
      },
    );

    test('a free cancel records no fee', () async {
      final c = controller();
      await c.create(draft());
      await c.cancel('rsv_r3', reason: 'plans_changed');
      expect(c.byId('rsv_r3')!.cancellationFee, isNull);
    });
  });

  group('mock dispatch demo script', () {
    test('a driver accepts soon after booking, well before the lead', () async {
      final c = controller(
        dispatch: MockReservationDispatch(driverChangeAfter: null),
      );
      addTearDown(c.dispose);
      await c.create(draft());

      await c.startLiveIfDue(now: bookedAt.add(const Duration(seconds: 5)));
      expect(c.byId('rsv_r3')!.status, ReservationStatus.scheduled);

      await c.startLiveIfDue(now: bookedAt.add(const Duration(seconds: 20)));
      final ride = c.byId('rsv_r3')!;
      expect(ride.status, ReservationStatus.driverAssigned);
      expect(ride.driver, isNotNull);
      expect(ride.driver!.id, startsWith('drv_mock_'));
      expect(ride.driver!.photoAsset, isNotNull);
      expect(ride.driver!.carLabel, isNotNull);
      expect(c.showsDriverOf(ride), isTrue);
    });

    test(
      'once, the accepted driver hands the ride to another driver',
      () async {
        final c = controller(dispatch: MockReservationDispatch());
        addTearDown(c.dispose);
        await c.create(draft());

        await c.startLiveIfDue(now: bookedAt.add(const Duration(seconds: 20)));
        final first = c.byId('rsv_r3')!.driver!;
        // First look starts the handover clock; nothing changes yet.
        await c.startLiveIfDue(now: bookedAt.add(const Duration(seconds: 30)));
        expect(c.byId('rsv_r3')!.driver!.isSameAs(first), isTrue);

        await c.startLiveIfDue(now: bookedAt.add(const Duration(seconds: 61)));
        final changed = c.byId('rsv_r3')!;
        expect(changed.status, ReservationStatus.driverAssigned);
        expect(changed.driverChanged, isTrue);
        expect(changed.previousDriver!.isSameAs(first), isTrue);
        expect(changed.driver!.isSameAs(first), isFalse);

        // Never a second time.
        await c.startLiveIfDue(now: bookedAt.add(const Duration(minutes: 10)));
        expect(c.byId('rsv_r3')!.driver!.isSameAs(changed.driver!), isTrue);
      },
    );

    test('no handover inside the assignment lead', () async {
      final c = controller(dispatch: MockReservationDispatch());
      addTearDown(c.dispose);
      await c.create(draft());
      final lead = pickupAt.subtract(const Duration(minutes: 30));

      await c.startLiveIfDue(now: lead);
      final first = c.byId('rsv_r3')!.driver!;
      await c.startLiveIfDue(now: lead.add(const Duration(minutes: 5)));
      await c.startLiveIfDue(now: lead.add(const Duration(minutes: 10)));
      expect(c.byId('rsv_r3')!.driver!.isSameAs(first), isTrue);
      expect(c.byId('rsv_r3')!.previousDriver, isNull);
    });

    test('a ride whose driver already left is not handed over again', () async {
      final c = controller(dispatch: MockReservationDispatch());
      addTearDown(c.dispose);
      await c.create(draft());
      await c.startLiveIfDue(now: bookedAt.add(const Duration(seconds: 20)));
      await c.driverCancelled('rsv_r3');
      await c.startLiveIfDue(now: bookedAt.add(const Duration(seconds: 30)));
      final second = c.byId('rsv_r3')!.driver!;
      expect(c.byId('rsv_r3')!.driverChanged, isTrue);

      await c.startLiveIfDue(now: bookedAt.add(const Duration(minutes: 5)));
      expect(c.byId('rsv_r3')!.driver!.isSameAs(second), isTrue);
    });
  });
}
