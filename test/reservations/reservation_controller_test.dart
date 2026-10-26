import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';

void main() {
  ReservationController controller() {
    return ReservationController(
      store: LocalReservationRepository(
        storage: MemoryReservationStorage(),
        nextId: () => 'rsv_ctrl',
      ),
    );
  }

  final draft = ReservationDraft(
    scheduledPickupAt: DateTime(2026, 9, 23, 6, 55),
    pickup: const ReservationPlace(label: 'Klockarvägen 37'),
    destination: const ReservationPlace(label: 'T-Centralen'),
    categoryId: 'comfort',
    categoryName: 'Comfort',
    categoryImage: 'assets/images/rides/comfort.webp',
    price: 339,
    paymentMethod: 'Cash',
  );

  const realDriver = ReservationDriver(
    firstName: 'Amina',
    rating: 4.9,
    vehicle: 'Volvo EX40',
    plate: 'ABC 123',
  );

  test('opening details does not create another reservation', () async {
    final c = controller();
    await c.create(draft);
    expect(c.all, hasLength(1));
    expect(c.byId('rsv_ctrl')?.reservationId, 'rsv_ctrl');
    expect(c.byId('rsv_ctrl')?.reservationId, 'rsv_ctrl');
    expect(c.all, hasLength(1));
  });

  test(
    'Phase 134: concurrent cancel calls for the same reservation coalesce '
    'onto one in-flight Future instead of racing two store mutations',
    () async {
      final c = controller();
      await c.create(draft);
      final first = c.cancel('rsv_ctrl', reason: 'first');
      final second = c.cancel('rsv_ctrl', reason: 'second');
      expect(
        identical(first, second),
        isTrue,
        reason: 'the second call must reuse the first in-flight Future',
      );
      final result = await first;
      expect(await second, same(result));
      expect(result.status, ReservationStatus.cancelled);
      expect(
        result.cancellationReason,
        'first',
        reason: 'only the first call actually mutated the store',
      );

      // Once resolved, a later call must not be stuck reusing a stale Future.
      final third = c.cancel('rsv_ctrl', reason: 'third');
      expect(identical(third, first), isFalse);
      await third;
    },
  );

  test(
    'Phase 134: concurrent update calls for the same reservation coalesce',
    () async {
      final c = controller();
      await c.create(draft);
      final patch = ReservationPatch(
        scheduledPickupAt: DateTime(2026, 9, 24, 8, 15),
      );
      final first = c.update('rsv_ctrl', patch);
      final second = c.update('rsv_ctrl', patch);
      expect(identical(first, second), isTrue);
      await first;
      await second;
    },
  );

  test('Phase 134: concurrent create calls coalesce onto one Future', () async {
    final c = controller();
    final first = c.create(draft);
    final second = c.create(draft);
    expect(identical(first, second), isTrue);
    final result = await first;
    expect(await second, same(result));
    expect(c.all, hasLength(1), reason: 'only one reservation was created');
  });

  test('tabs split upcoming completed cancelled', () async {
    final c = controller();
    await c.create(draft);
    expect(c.upcoming(), hasLength(1));
    expect(c.cancelled(), isEmpty);
    await c.cancel('rsv_ctrl', reason: 'plans_changed');
    expect(c.upcoming(), isEmpty);
    expect(c.cancelled(), hasLength(1));
    expect(c.completed(), isEmpty);
  });

  test(
    'missing driver payload stays pending on the same reservation',
    () async {
      final c = controller();
      await c.create(draft);
      await c.assignMockDriver('rsv_ctrl');
      final ride = c.byId('rsv_ctrl')!;
      expect(ride.status, ReservationStatus.driverAssignmentPending);
      expect(ride.driverAssigned, isFalse);
      expect(ride.driver, isNull);
      expect(c.upcoming(), hasLength(1));
    },
  );

  test('explicit driver assignment is the same reservation', () async {
    final c = controller();
    await c.create(draft);
    await c.assignMockDriver('rsv_ctrl', driver: realDriver);
    final ride = c.byId('rsv_ctrl')!;
    expect(ride.status, ReservationStatus.driverAssigned);
    expect(ride.driverAssigned, isTrue);
    expect(ride.driver?.firstName, 'Amina');
    expect(ride.driver?.plate, 'ABC 123');
    expect(c.upcoming(), hasLength(1));
  });

  test('plan return waits for explicit create', () async {
    var n = 0;
    final c = ReservationController(
      store: LocalReservationRepository(
        storage: MemoryReservationStorage(),
        nextId: () => 'rsv_${++n}',
      ),
    );
    final origin = await c.create(draft);
    expect(c.all, hasLength(1));
    final ret = await c.planReturn(
      origin,
      scheduledPickupAt: DateTime(2026, 9, 24, 18, 30),
    );
    expect(ret.reservationId, isNot(origin.reservationId));
    expect(ret.pickup.label, origin.destination.label);
    expect(ret.destination.label, origin.pickup.label);
    expect(c.all, hasLength(2));
  });

  test('return ride can choose a different category', () async {
    var n = 0;
    final c = ReservationController(
      store: LocalReservationRepository(
        storage: MemoryReservationStorage(),
        nextId: () => 'rsv_${++n}',
      ),
    );
    final origin = await c.create(draft);
    final ret = await c.planReturn(
      origin,
      scheduledPickupAt: DateTime(2026, 9, 24, 18, 30),
      categoryId: 'xl',
      categoryName: 'Movera XL',
      categoryImage: 'assets/images/rides/xl.webp',
      passengerCount: 6,
      price: 399,
      note: 'Bags · Pet',
    );
    expect(ret.reservationId, isNot(origin.reservationId));
    expect(origin.reservationId, 'rsv_1');
    expect(ret.categoryId, 'xl');
    expect(ret.categoryName, 'Movera XL');
    expect(ret.passengerCount, 6);
    expect(ret.note, 'Bags · Pet');
    expect(origin.categoryId, 'comfort');
    expect(c.byId(origin.reservationId)!.categoryId, 'comfort');
    expect(c.all, hasLength(2));
  });

  test('edits and cancel keep the same reservation id', () async {
    final c = controller();
    await c.create(draft);
    final updated = await c.update(
      'rsv_ctrl',
      const ReservationPatch(paymentMethod: 'Swish', note: 'Child'),
    );
    expect(updated.reservationId, 'rsv_ctrl');
    expect(updated.categoryName, 'Comfort');
    expect(updated.note, 'Child');
    final cancelled = await c.cancel('rsv_ctrl', reason: 'plans_changed');
    expect(cancelled.reservationId, 'rsv_ctrl');
    expect(cancelled.status, ReservationStatus.cancelled);
    expect(c.all, hasLength(1));
  });
}
