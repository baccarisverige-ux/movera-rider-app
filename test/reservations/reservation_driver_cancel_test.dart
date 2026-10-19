import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A driver dropping a scheduled ride is not the rider cancelling it. The
/// reservation stands — same time, route and price — and goes back to waiting
/// for a driver.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<(ReservationController, Reservation)> booked() async {
    final controller = ReservationController(
      store: LocalReservationRepository(),
    );
    final made = await controller.create(
      ReservationDraft(
        scheduledPickupAt: DateTime.now().add(const Duration(hours: 4)),
        pickup: const ReservationPlace(
          label: 'Sveavägen 1',
          lat: 59.34,
          lng: 18.05,
        ),
        destination: const ReservationPlace(
          label: 'Hornsgatan 2',
          lat: 59.31,
          lng: 18.04,
        ),
        categoryId: 'economy',
        categoryName: 'Movera',
        categoryImage: 'assets/images/rides/movera.webp',
        price: 259,
        paymentMethod: 'Apple Pay',
      ),
    );
    final assigned = await controller.assignMockDriver(
      made.reservationId,
      driver: const ReservationDriver(firstName: 'Elin', rating: 4.9),
    );
    return (controller, assigned);
  }

  test('a dropped scheduled ride returns to waiting for a driver', () async {
    final (controller, assigned) = await booked();
    expect(assigned.status, ReservationStatus.driverAssigned);

    final after = await controller.driverCancelled(assigned.reservationId);

    expect(after.status, ReservationStatus.driverAssignmentPending);
    expect(after.status.isCancelled, isFalse);
    expect(after.driver, isNull);
  });

  test('the reservation itself is unchanged', () async {
    final (controller, assigned) = await booked();
    final after = await controller.driverCancelled(assigned.reservationId);

    expect(after.scheduledPickupAt, assigned.scheduledPickupAt);
    expect(after.pickup.label, assigned.pickup.label);
    expect(after.destination.label, assigned.destination.label);
    expect(after.price, assigned.price);
    expect(after.paymentMethod, assigned.paymentMethod);
  });

  test('it stays in upcoming, not in cancelled', () async {
    final (controller, assigned) = await booked();
    await controller.driverCancelled(assigned.reservationId);

    expect(
      controller.upcoming().map((r) => r.reservationId),
      contains(assigned.reservationId),
    );
    expect(controller.cancelled(), isEmpty);
  });

  test('a new driver can then be assigned', () async {
    final (controller, assigned) = await booked();
    await controller.driverCancelled(assigned.reservationId);

    final again = await controller.assignMockDriver(
      assigned.reservationId,
      driver: const ReservationDriver(firstName: 'Johan', rating: 4.8),
    );
    expect(again.status, ReservationStatus.driverAssigned);
    expect(again.driver?.firstName, 'Johan');
  });

  test('a rider cancellation still cancels', () async {
    final (controller, assigned) = await booked();
    final cancelled = await controller.cancel(assigned.reservationId);

    expect(cancelled.status, ReservationStatus.cancelled);
    expect(controller.cancelled(), isNotEmpty);
  });

  test('dropping a ride with no driver changes nothing', () async {
    final (controller, assigned) = await booked();
    await controller.driverCancelled(assigned.reservationId);
    final again = await controller.driverCancelled(assigned.reservationId);

    expect(again.status, ReservationStatus.driverAssignmentPending);
  });
}
