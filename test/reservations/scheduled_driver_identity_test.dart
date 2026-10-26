import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';

ReservationDraft _draft(DateTime pickupAt) {
  return ReservationDraft(
    scheduledPickupAt: pickupAt,
    pickup: const ReservationPlace(label: 'Pickup'),
    destination: const ReservationPlace(label: 'Destination'),
    categoryId: 'comfort',
    categoryName: 'Comfort',
    categoryImage: 'assets/images/rides/comfort.webp',
    price: 300,
    paymentMethod: 'Apple Pay',
  );
}

void main() {
  test('near pickup time never fabricates scheduled driver identity', () async {
    final store = LocalReservationRepository(
      storage: MemoryReservationStorage(),
      nextId: () => 'scheduled_no_driver',
    );
    final controller = ReservationController(store: store);
    final pickupAt = DateTime(2026, 9, 15, 12, 0);

    await controller.create(_draft(pickupAt));
    await controller.startLiveIfDue(
      now: pickupAt.subtract(const Duration(minutes: 1)),
    );

    final ride = controller.byId('scheduled_no_driver')!;
    expect(ride.status, ReservationStatus.driverAssignmentPending);
    expect(ride.driver, isNull);
    expect(ride.driverAssigned, isFalse);
    expect(ride.revealsDriver, isFalse);
  });

  test(
    'real scheduled driver payload is preserved when ride goes en route',
    () async {
      final store = LocalReservationRepository(
        storage: MemoryReservationStorage(),
        nextId: () => 'scheduled_real_driver',
      );
      final controller = ReservationController(store: store);
      final pickupAt = DateTime(2026, 9, 15, 12, 0);
      const realDriver = ReservationDriver(
        firstName: 'Test Driver',
        rating: 4.8,
        vehicle: 'Test Vehicle',
        plate: 'TEST 1',
      );

      await controller.create(_draft(pickupAt));
      await controller.assignMockDriver(
        'scheduled_real_driver',
        driver: realDriver,
      );
      await controller.startLiveIfDue(
        now: pickupAt.subtract(const Duration(minutes: 1)),
      );

      final ride = controller.byId('scheduled_real_driver')!;
      expect(ride.status, ReservationStatus.driverEnRoute);
      expect(ride.driver, same(realDriver));
      expect(ride.driverAssigned, isTrue);
      expect(ride.revealsDriver, isTrue);
    },
  );
}
