import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';
import 'package:movera_rider/features/trips/domain/trip.dart';

/// A storage whose writes wait while [closed] is set, like a slow prefs
/// write that is still in flight.
class _GatedStorage extends MemoryReservationStorage {
  Completer<void>? _gate;

  void close() => _gate = Completer<void>();

  void open() {
    _gate?.complete();
    _gate = null;
  }

  @override
  Future<void> write(String json) async {
    final gate = _gate;
    if (gate != null) await gate.future;
    await super.write(json);
  }
}

const _driver = ReservationDriver(
  firstName: 'Amina',
  rating: 4.9,
  vehicle: 'Volvo EX40',
  plate: 'ABC 123',
);

ReservationDraft _draft() => ReservationDraft(
  scheduledPickupAt: DateTime.utc(2026, 10, 22, 8),
  pickup: const ReservationPlace(label: 'Home'),
  destination: const ReservationPlace(label: 'Work'),
  categoryId: 'economy',
  categoryName: 'Movera',
  categoryImage: 'assets/images/rides/movera.webp',
  price: 300,
  paymentMethod: 'Apple Pay',
);

/// rider-u159: a lifecycle write that was decided before the rider's
/// cancel committed, and queued behind it, overwrote the cancelled status
/// and brought the ride back to life.
void main() {
  late _GatedStorage storage;
  late LocalReservationRepository store;
  late String id;

  setUp(() async {
    storage = _GatedStorage();
    store = LocalReservationRepository(
      storage: storage,
      nextId: () => 'rsv-race',
    );
    id = (await store.createReservation(_draft())).reservationId;
    await store.assignDriver(id, driver: _driver);
    await store.updateReservation(
      id,
      const ReservationPatch(status: ReservationStatus.driverEnRoute),
    );
  });

  test(
    'a status step queued behind a cancel leaves the ride cancelled',
    () async {
      storage.close();
      final cancel = store.cancelReservation(id, reason: 'rider_cancelled');
      // The mock trip still sees driverEnRoute and queues its next step.
      expect(store.cached.single.status, ReservationStatus.driverEnRoute);
      final step = store.updateReservation(
        id,
        const ReservationPatch(status: ReservationStatus.driverArrived),
      );
      storage.open();
      await cancel;
      await step;

      final ride = store.cached.single;
      expect(ride.status, ReservationStatus.cancelled);
      expect(ride.cancellationActor, TripCancellationActor.rider);
    },
  );

  test(
    'a driver assignment queued behind a cancel leaves it cancelled',
    () async {
      storage.close();
      final cancel = store.cancelReservation(id, reason: 'rider_cancelled');
      final assign = store.assignDriver(id);
      storage.open();
      await cancel;
      await assign;

      expect(store.cached.single.status, ReservationStatus.cancelled);
    },
  );
}
