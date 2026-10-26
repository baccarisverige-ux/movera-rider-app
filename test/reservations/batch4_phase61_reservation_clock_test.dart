import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';

void main() {
  final pickupAt = DateTime.utc(2026, 9, 25, 12);
  late DateTime clock;
  late ReservationController controller;

  const driver = ReservationDriver(firstName: 'Amina');

  ReservationDraft draft() => ReservationDraft(
    scheduledPickupAt: pickupAt,
    pickup: const ReservationPlace(label: 'Pickup'),
    destination: const ReservationPlace(label: 'Destination'),
    categoryId: 'comfort',
    categoryName: 'Comfort',
    categoryImage: 'comfort.webp',
    price: 300,
    paymentMethod: 'Cash',
  );

  setUp(() async {
    clock = pickupAt.subtract(const Duration(minutes: 10));
    controller = ReservationController(
      store: LocalReservationRepository(
        storage: MemoryReservationStorage(),
        nextId: () => 'phase61',
        clock: () => clock,
      ),
      clock: () => clock,
    );
    await controller.create(draft());
  });

  test('T-10 and T-1 keep one reservation and lifecycle drives countdown eligibility', () async {
    await controller.startLiveIfDue();
    expect(controller.byId('phase61')!.status, ReservationStatus.scheduled);

    clock = pickupAt.subtract(const Duration(minutes: 1));
    await controller.startLiveIfDue();
    expect(
      controller.byId('phase61')!.status,
      ReservationStatus.driverAssignmentPending,
    );
    expect(controller.upcoming(), hasLength(1));
  });

  test(
    'T, T+30s and T+5m cannot resurrect or duplicate assignment lifecycle',
    () async {
      clock = pickupAt;
      await controller.startLiveIfDue();
      expect(
        controller.byId('phase61')!.status,
        ReservationStatus.driverAssignmentPending,
      );

      for (final offset in [
        const Duration(seconds: 30),
        const Duration(minutes: 5),
      ]) {
        clock = pickupAt.add(offset);
        await controller.startLiveIfDue();
        expect(
          controller.byId('phase61')!.status,
          ReservationStatus.driverAssignmentPending,
        );
        expect(controller.all, hasLength(1));
      }
    },
  );

  test(
    'passed active scheduled ride is never deleted or clock-advanced',
    () async {
      await controller.assignMockDriver('phase61', driver: driver);
      await controller.update(
        'phase61',
        const ReservationPatch(status: ReservationStatus.inProgress),
      );

      clock = pickupAt.add(const Duration(minutes: 5));
      await controller.startLiveIfDue();

      final ride = controller.byId('phase61')!;
      expect(ride.status, ReservationStatus.inProgress);
      expect(ride.driver?.firstName, 'Amina');
      expect(controller.all, hasLength(1));
    },
  );

  test(
    'background across T converges to the same lifecycle on resume tick',
    () async {
      clock = pickupAt.subtract(const Duration(minutes: 10));
      await controller.startLiveIfDue();
      expect(controller.byId('phase61')!.status, ReservationStatus.scheduled);

      clock = pickupAt.add(const Duration(seconds: 30));
      await controller.startLiveIfDue();

      expect(
        controller.byId('phase61')!.status,
        ReservationStatus.driverAssignmentPending,
      );
    },
  );

  test(
    'real assigned driver advances en-route without changing identity',
    () async {
      await controller.assignMockDriver('phase61', driver: driver);
      clock = pickupAt.add(const Duration(minutes: 5));

      await controller.startLiveIfDue();

      final ride = controller.byId('phase61')!;
      expect(ride.status, ReservationStatus.driverEnRoute);
      expect(ride.driver?.firstName, 'Amina');
    },
  );
}
