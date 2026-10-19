import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_trip_adapter.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';
import 'package:movera_rider/features/trips/domain/trip.dart';
import 'package:movera_rider/features/trips/domain/trip_status.dart';

void main() {
  final fixedNow = DateTime.utc(2026, 9, 23, 5);

  ReservationDraft draft() => ReservationDraft(
    scheduledPickupAt: DateTime.utc(2026, 9, 24, 10),
    pickup: const ReservationPlace(label: 'A'),
    destination: const ReservationPlace(label: 'B'),
    categoryId: 'economy',
    categoryName: 'Movera',
    categoryImage: 'assets/images/rides/movera.webp',
    price: 259,
    paymentMethod: 'apple',
  );

  test('scheduled reservation projects into the shared Trip contract', () async {
    final repo = LocalReservationRepository(
      storage: MemoryReservationStorage(),
      nextId: () => 'trip-scheduled-1',
      clock: () => fixedNow,
    );

    final reservation = await repo.createReservation(draft());
    final trip = reservation.toTripContract();

    expect(trip.tripId, reservation.reservationId);
    expect(trip.status, TripStatus.requested);
    expect(trip.schedule?.scheduledFor, reservation.scheduledPickupAt);
    expect(trip.categoryId, 'economy');
    expect(trip.paymentMethodId, 'apple');
  });

  test('scheduled cancellation records actor reason and timestamp', () async {
    final repo = LocalReservationRepository(
      storage: MemoryReservationStorage(),
      nextId: () => 'trip-scheduled-2',
      clock: () => fixedNow,
    );
    await repo.createReservation(draft());

    final cancelled = await repo.cancelReservation(
      'trip-scheduled-2',
      reason: 'plans_changed',
    );

    expect(cancelled.cancellationActor, TripCancellationActor.rider);
    expect(cancelled.cancellationReason, 'plans_changed');
    expect(cancelled.cancelledAt, fixedNow);

    final trip = cancelled.toTripContract();
    expect(trip.status, TripStatus.cancelledByRider);
    expect(trip.cancellation?.actor, TripCancellationActor.rider);
    expect(trip.cancellation?.reasonId, 'plans_changed');
    expect(trip.cancellation?.at, fixedNow);
  });

  test('cancellation metadata survives persistence round trip', () async {
    final storage = MemoryReservationStorage();
    final repo = LocalReservationRepository(
      storage: storage,
      nextId: () => 'trip-scheduled-3',
      clock: () => fixedNow,
    );
    await repo.createReservation(draft());
    await repo.cancelReservation('trip-scheduled-3', reason: 'duplicate');

    final restored = LocalReservationRepository(storage: storage);
    await restored.hydrate();
    final item = await restored.getReservation('trip-scheduled-3');

    expect(item?.cancellationActor, TripCancellationActor.rider);
    expect(item?.cancellationReason, 'duplicate');
    expect(item?.cancelledAt, fixedNow);
  });
  test('scheduled Trip convergence preserves every cancellation actor', () {
    Reservation cancelledBy(TripCancellationActor actor) => Reservation(
      reservationId: 'scheduled-${actor.name}',
      createdAt: fixedNow,
      scheduledPickupAt: fixedNow.add(const Duration(hours: 2)),
      pickup: const ReservationPlace(label: 'A'),
      destination: const ReservationPlace(label: 'B'),
      categoryId: 'economy',
      categoryName: 'Movera',
      categoryImage: 'assets/images/rides/movera.webp',
      price: 259,
      paymentMethod: 'apple',
      status: ReservationStatus.cancelled,
      cancellationActor: actor,
      cancellationReason: 'cancelled',
      cancelledAt: fixedNow,
    );

    expect(
      cancelledBy(TripCancellationActor.rider).toTripContract().status,
      TripStatus.cancelledByRider,
    );
    expect(
      cancelledBy(TripCancellationActor.driver).toTripContract().status,
      TripStatus.cancelledByDriver,
    );
    expect(
      cancelledBy(TripCancellationActor.admin).toTripContract().status,
      TripStatus.cancelledByAdmin,
    );
    expect(
      cancelledBy(TripCancellationActor.system).toTripContract().status,
      TripStatus.failed,
    );
  });

}
