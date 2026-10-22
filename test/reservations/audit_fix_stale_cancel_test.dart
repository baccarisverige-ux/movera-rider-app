import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';

const _driver = ReservationDriver(
  firstName: 'Amina',
  rating: 4.9,
  vehicle: 'Volvo EX40',
  plate: 'ABC 123',
);

/// rider-u170: the Upcoming page confirmed a cancel against the ride it
/// had when the sheet opened. When the ride had meanwhile gone live and
/// been completed, the cancel rewrote the completed trip as cancelled by
/// the rider with a late fee.
void main() {
  test(
    'a cancel that lands after the ride completed changes nothing',
    () async {
      final controller = ReservationController(
        store: LocalReservationRepository(
          storage: MemoryReservationStorage(),
          nextId: () => 'rsv-stale',
        ),
      );
      final ride = await controller.create(
        ReservationDraft(
          scheduledPickupAt: DateTime.utc(2026, 10, 21, 21, 50),
          pickup: const ReservationPlace(label: 'Home'),
          destination: const ReservationPlace(label: 'Work'),
          categoryId: 'economy',
          categoryName: 'Movera',
          categoryImage: 'assets/images/rides/movera.webp',
          price: 300,
          paymentMethod: 'Apple Pay',
        ),
      );
      final id = ride.reservationId;
      // The sheet opens on the assigned ride; meanwhile the trip runs to the
      // end.
      await controller.applyDriverAssignment(id, driver: _driver);
      for (final status in [
        ReservationStatus.driverEnRoute,
        ReservationStatus.driverArrived,
        ReservationStatus.inProgress,
        ReservationStatus.completed,
      ]) {
        await controller.update(id, ReservationPatch(status: status));
      }

      await controller.cancel(
        id,
        reason: 'changed_plans',
        fee: const Money(5000, 'SEK'),
      );

      final after = controller.byId(id)!;
      expect(after.status, ReservationStatus.completed);
      expect(after.cancellationFee, isNull);
      expect(after.cancellationActor, isNull);
      expect(after.cancelledAt, isNull);
    },
  );
}
