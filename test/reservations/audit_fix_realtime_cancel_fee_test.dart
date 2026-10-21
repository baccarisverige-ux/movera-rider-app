import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/application/reservation_ride_realtime.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';

/// rider-65: the live-screen sheet's cancel already applies the
/// reservation's terms (rider-u53), but the reservation's realtime cancel
/// still cancelled with no fee, inside the late window.
void main() {
  test('the realtime cancel records the reservation\'s late fee', () async {
    // Two minutes before pickup: inside the default 60-minute window.
    final pickup = DateTime.utc(2026, 10, 21, 21, 50);
    final now = pickup.subtract(const Duration(minutes: 2));
    final controller = ReservationController(
      store: LocalReservationRepository(
        storage: MemoryReservationStorage(),
        nextId: () => 'rsv-rt-fee',
        clock: () => now,
      ),
      clock: () => now,
    );
    final ride = await controller.create(
      ReservationDraft(
        scheduledPickupAt: pickup,
        pickup: const ReservationPlace(label: 'Home'),
        destination: const ReservationPlace(label: 'Work'),
        categoryId: 'economy',
        categoryName: 'Movera',
        categoryImage: 'assets/images/rides/movera.webp',
        price: 300,
        paymentMethod: 'Apple Pay',
      ),
    );
    await controller.applyDriverAssignment(
      ride.reservationId,
      driver: const ReservationDriver(firstName: 'Amina', rating: 4.9),
    );
    await controller.update(
      ride.reservationId,
      const ReservationPatch(status: ReservationStatus.driverEnRoute),
    );
    final expected = controller.cancelTermsFor(
      controller.byId(ride.reservationId)!,
    );
    expect(expected.fee, isNotNull);
    expect(expected.fee!.isPositive, isTrue);

    final realtime = ReservationRideRealtime(
      controller: controller,
      reservationId: ride.reservationId,
    );
    addTearDown(realtime.dispose);
    realtime.cancelRide();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final after = controller.byId(ride.reservationId)!;
    expect(after.status, ReservationStatus.cancelled);
    expect(after.cancellationFee, expected.fee);
    expect(after.cancellationFee, isA<Money>());
  });
}
