import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';

ReservationDraft _draft({
  DateTime? when,
  String pickup = 'Klockarvägen 37',
  String dropoff = 'Stockholm C',
  String payment = 'Apple Pay',
  String? parent,
  String? note,
}) {
  return ReservationDraft(
    scheduledPickupAt: when ?? DateTime(2026, 9, 23, 6, 55),
    estimatedDropoffAt: (when ?? DateTime(2026, 9, 23, 6, 55)).add(
      const Duration(minutes: 31),
    ),
    pickup: ReservationPlace(label: pickup, subtitle: 'Södertälje'),
    destination: ReservationPlace(label: dropoff, subtitle: 'Stockholm'),
    categoryId: 'economy',
    categoryName: 'Movera',
    categoryImage: 'assets/images/rides/movera.webp',
    price: 522,
    paymentMethod: payment,
    parentReservationId: parent,
    note: note,
  );
}

void main() {
  test('create keeps a stable id and scheduled status', () async {
    var n = 0;
    final store = LocalReservationRepository(
      storage: MemoryReservationStorage(),
      nextId: () => 'rsv_${++n}',
    );
    final created = await store.createReservation(_draft());
    expect(created.reservationId, 'rsv_1');
    expect(created.status, ReservationStatus.scheduled);
    expect(created.driver, isNull);
    expect(created.paymentMethod, 'Apple Pay');
    expect(await store.getUpcomingReservations(), hasLength(1));
  });

  test('corrupt local data is ignored instead of crashing', () async {
    final store = LocalReservationRepository(
      storage: MemoryReservationStorage('{"nope": true}'),
    );
    await store.hydrate();
    expect(store.cached, isEmpty);
    final created = await store.createReservation(_draft());
    expect(created.reservationId, isNotEmpty);
  });

  test('legacy missing fields still parse', () {
    final ride = Reservation.tryParse({
      'id': 'old-1',
      'createdAt': '2026-09-01T10:00:00.000',
      'pickupAt': '2026-09-23T06:55:00.000',
      'pickup': 'Home',
      'destination': {'label': 'Work'},
    });
    expect(ride, isNotNull);
    expect(ride!.reservationId, 'old-1');
    expect(ride.pickup.label, 'Home');
    expect(ride.status, ReservationStatus.scheduled);
  });

  test('update time does not reset payment destination or category', () async {
    final store = LocalReservationRepository(
      storage: MemoryReservationStorage(),
    );
    final created = await store.createReservation(_draft());
    final updated = await store.updateReservation(
      created.reservationId,
      ReservationPatch(scheduledPickupAt: DateTime(2026, 10, 1, 8, 0)),
    );
    expect(updated.reservationId, created.reservationId);
    expect(updated.paymentMethod, 'Apple Pay');
    expect(updated.destination.label, 'Stockholm C');
    expect(updated.categoryName, 'Movera');
    expect(updated.scheduledPickupAt, DateTime(2026, 10, 1, 8, 0));
  });

  test('edit pickup keeps the same reservation id', () async {
    final store = LocalReservationRepository(
      storage: MemoryReservationStorage(),
    );
    final created = await store.createReservation(_draft());
    final updated = await store.updateReservation(
      created.reservationId,
      const ReservationPatch(
        pickup: ReservationPlace(label: 'Arlanda Express'),
      ),
    );
    expect(updated.reservationId, created.reservationId);
    expect(updated.pickup.label, 'Arlanda Express');
    expect(updated.destination.label, 'Stockholm C');
  });

  test('edit destination keeps the same reservation id', () async {
    final store = LocalReservationRepository(
      storage: MemoryReservationStorage(),
    );
    final created = await store.createReservation(_draft());
    final updated = await store.updateReservation(
      created.reservationId,
      const ReservationPatch(
        destination: ReservationPlace(label: 'Arlanda Terminal 5'),
      ),
    );
    expect(updated.reservationId, created.reservationId);
    expect(updated.destination.label, 'Arlanda Terminal 5');
    expect(updated.pickup.label, 'Klockarvägen 37');
    expect(store.cached, hasLength(1));
  });

  test('edit payment keeps the same reservation id', () async {
    final store = LocalReservationRepository(
      storage: MemoryReservationStorage(),
    );
    final created = await store.createReservation(_draft());
    final updated = await store.updateReservation(
      created.reservationId,
      const ReservationPatch(paymentMethod: 'Swish'),
    );
    expect(updated.reservationId, created.reservationId);
    expect(updated.paymentMethod, 'Swish');
    expect(updated.categoryName, 'Movera');
    expect(store.cached, hasLength(1));
  });

  test('cancel keeps the reservation in history', () async {
    final store = LocalReservationRepository(
      storage: MemoryReservationStorage(),
    );
    final created = await store.createReservation(_draft());
    await store.cancelReservation(
      created.reservationId,
      reason: 'plans_changed',
    );
    expect(await store.getUpcomingReservations(), isEmpty);
    final history = await store.getRideHistory();
    expect(history, hasLength(1));
    expect(history.first.status, ReservationStatus.cancelled);
    expect(history.first.reservationId, created.reservationId);
    expect(history.first.cancellationReason, 'plans_changed');
  });

  test('missing driver payload stays pending without inventing identity', () async {
    final store = LocalReservationRepository(
      storage: MemoryReservationStorage(),
    );
    final created = await store.createReservation(_draft());
    final pending = await store.assignDriver(created.reservationId);
    expect(pending.reservationId, created.reservationId);
    expect(pending.status, ReservationStatus.driverAssignmentPending);
    expect(pending.driver, isNull);
    expect(pending.driverAssigned, isFalse);
    expect(await store.getUpcomingReservations(), hasLength(1));
  });

  test('explicit driver payload updates the same reservation', () async {
    final store = LocalReservationRepository(
      storage: MemoryReservationStorage(),
    );
    final created = await store.createReservation(_draft());
    const driver = ReservationDriver(
      firstName: 'Amina',
      rating: 4.9,
      vehicle: 'Volvo EX40',
      plate: 'ABC 123',
    );
    final assigned = await store.assignDriver(
      created.reservationId,
      driver: driver,
    );
    expect(assigned.reservationId, created.reservationId);
    expect(assigned.status, ReservationStatus.driverAssigned);
    expect(assigned.driver?.firstName, 'Amina');
    expect(assigned.driver?.plate, 'ABC 123');
    expect(await store.getUpcomingReservations(), hasLength(1));
  });

  test('restore after hydrate does not duplicate', () async {
    final memory = MemoryReservationStorage();
    final first = LocalReservationRepository(
      storage: memory,
      nextId: () => 'rsv_keep',
    );
    await first.createReservation(_draft());
    final restored = LocalReservationRepository(storage: memory);
    await restored.hydrate();
    expect(restored.cached, hasLength(1));
    expect(restored.cached.single.reservationId, 'rsv_keep');
    await restored.hydrate();
    expect(restored.cached, hasLength(1));
    expect(restored.cached.single.reservationId, 'rsv_keep');
  });

  test('preferences survive restore on the same reservation', () async {
    final memory = MemoryReservationStorage();
    final first = LocalReservationRepository(
      storage: memory,
      nextId: () => 'rsv_note',
    );
    await first.createReservation(_draft(note: 'Bags · Pet'));
    final restored = LocalReservationRepository(storage: memory);
    await restored.hydrate();
    expect(restored.cached, hasLength(1));
    expect(restored.cached.single.reservationId, 'rsv_note');
    expect(restored.cached.single.note, 'Bags · Pet');
    expect(restored.cached.single.hasPreferences, isTrue);
  });

  test('return ride is a new id only after create', () async {
    var n = 0;
    final store = LocalReservationRepository(
      storage: MemoryReservationStorage(),
      nextId: () => 'rsv_${++n}',
    );
    final origin = await store.createReservation(_draft());
    expect(store.cached, hasLength(1));
    final ret = await store.createReservation(
      _draft(
        pickup: origin.destination.label,
        dropoff: origin.pickup.label,
        parent: origin.reservationId,
        when: DateTime(2026, 9, 23, 18, 0),
      ),
    );
    expect(ret.reservationId, isNot(origin.reservationId));
    expect(ret.parentReservationId, origin.reservationId);
    expect(store.cached, hasLength(2));
  });
}
