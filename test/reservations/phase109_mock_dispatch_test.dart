import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/data/mock_reservation_dispatch.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_dispatch.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';

/// Batch 10 Phase 109 — unit coverage for the injected mock dispatch.
/// These use the new `mockDispatch:` seam, so they cannot run on the base
/// commit; the reproduce-first coverage is
/// `phase109_reservation_lifecycle_test.dart`.
void main() {
  final pickupAt = DateTime(2026, 10, 1, 12);
  const demo = AppEnv(
    flavor: AppFlavor.demo,
    apiBaseUrl: 'https://api.demo.movera.invalid',
  );
  const production = AppEnv(
    flavor: AppFlavor.production,
    apiBaseUrl: 'https://api.movera.example',
  );

  ReservationController controller({
    ReservationDispatch? dispatch,
    AppEnv environment = demo,
    MemoryReservationStorage? storage,
  }) {
    return ReservationController(
      store: LocalReservationRepository(
        storage: storage ?? MemoryReservationStorage(),
        nextId: () => 'rsv_109',
      ),
      environment: environment,
      mockDispatch: dispatch,
    );
  }

  Future<String> schedule(ReservationController c) async {
    final created = await c.create(
      ReservationDraft(
        scheduledPickupAt: pickupAt,
        pickup: const ReservationPlace(label: 'Stockholm Central'),
        destination: const ReservationPlace(label: 'Arlanda Airport'),
        categoryId: 'economy',
        categoryName: 'Movera',
        categoryImage: 'assets/images/rides/movera.webp',
        price: 459,
        paymentMethod: 'Visa •••• 4242',
      ),
    );
    return created.reservationId;
  }

  test('dispatch that finds nobody keeps today\'s path: searching at T-2, '
      'No driver found at T+5', () async {
    final c = controller(dispatch: _NobodyDispatch());
    final id = await schedule(c);

    await c.startLiveIfDue(now: pickupAt.subtract(const Duration(minutes: 30)));
    expect(c.byId(id)!.status, ReservationStatus.scheduled);

    await c.startLiveIfDue(now: pickupAt.subtract(const Duration(minutes: 2)));
    expect(c.byId(id)!.status, ReservationStatus.driverAssignmentPending);
    expect(c.byId(id)!.isSearchingDriver, isTrue);

    final late = pickupAt.add(ReservationController.noDriverFoundAfter);
    await c.startLiveIfDue(now: late);
    expect(c.isNoDriverFound(c.byId(id)!, now: late), isTrue);
    expect(c.byId(id)!.driver, isNull);
  });

  test('a dispatch passed to a non-mock environment is ignored', () async {
    final dispatch = _CountingDispatch();
    final c = controller(dispatch: dispatch, environment: production);
    final id = await schedule(c);

    await c.startLiveIfDue(now: pickupAt.subtract(const Duration(minutes: 30)));
    await c.startLiveIfDue(now: pickupAt.subtract(const Duration(minutes: 2)));
    expect(dispatch.asked, 0);
    expect(c.byId(id)!.status, ReservationStatus.driverAssignmentPending);
    expect(c.byId(id)!.driver, isNull);
  });

  test(
    'without a dispatch the demo controller never fabricates a driver',
    () async {
      final c = controller();
      final id = await schedule(c);
      await c.startLiveIfDue(
        now: pickupAt.subtract(const Duration(minutes: 30)),
      );
      expect(c.byId(id)!.status, ReservationStatus.scheduled);
      await c.startLiveIfDue(
        now: pickupAt.subtract(const Duration(minutes: 2)),
      );
      expect(c.byId(id)!.status, ReservationStatus.driverAssignmentPending);
      expect(c.byId(id)!.driver, isNull);
    },
  );

  test('first tick inside the window after T-2 but before T+5 assigns and '
      'goes en route in one tick', () async {
    final c = controller(dispatch: MockReservationDispatch());
    addTearDown(c.dispose);
    final id = await schedule(c);

    await c.startLiveIfDue(now: pickupAt.add(const Duration(minutes: 3)));
    expect(c.byId(id)!.status, ReservationStatus.driverEnRoute);
    expect(c.byId(id)!.revealsDriver, isTrue);
  });

  test(
    'mock driver comes from the shared pool, mapped for the live screen',
    () async {
      final dispatch = MockReservationDispatch();
      final c = controller(dispatch: dispatch);
      addTearDown(c.dispose);
      final id = await schedule(c);
      await c.startLiveIfDue(
        now: pickupAt.subtract(const Duration(minutes: 30)),
      );
      final driver = c.byId(id)!.driver!;
      const known = {
        'Elin': ('Volvo XC40 Recharge', 'MVR 204'),
        'Johan': ('Volvo V60', 'MVR 771'),
        'Amina': ('Tesla Model Y', 'MVR 316'),
      };
      expect(known.keys, contains(driver.firstName));
      expect(driver.vehicle, known[driver.firstName]!.$1);
      expect(driver.plate, known[driver.firstName]!.$2);
      expect(driver.rating, isNotNull);
    },
  );

  test('after a driver drops the ride, the next tick re-offers it to a '
      'different mock driver', () async {
    final c = controller(dispatch: MockReservationDispatch());
    addTearDown(c.dispose);
    final id = await schedule(c);
    await c.startLiveIfDue(now: pickupAt.subtract(const Duration(minutes: 30)));
    final first = c.byId(id)!.driver!.firstName;

    await c.driverCancelled(id);
    expect(c.byId(id)!.status, ReservationStatus.driverAssignmentPending);
    expect(c.byId(id)!.driver, isNull);

    await c.startLiveIfDue(
      now: pickupAt.subtract(const Duration(minutes: 29, seconds: 30)),
    );
    expect(c.byId(id)!.status, ReservationStatus.driverAssigned);
    expect(c.byId(id)!.driver!.firstName, isNot(first));
  });

  testWidgets('an on-the-road ride restored after a restart resumes its '
      'mock trip to completed', (tester) async {
    final storage = MemoryReservationStorage();
    final before = controller(storage: storage);
    final id = await schedule(before);
    await before.applyDriverAssignment(
      id,
      driver: const ReservationDriver(firstName: 'Elin'),
    );
    await before.update(
      id,
      const ReservationPatch(status: ReservationStatus.driverArrived),
    );

    // "Restart": a fresh controller over the same persisted store.
    final after = controller(
      storage: storage,
      dispatch: MockReservationDispatch(
        boardAfter: const Duration(seconds: 2),
        tripDuration: const Duration(seconds: 3),
      ),
    );
    await after.hydrate();
    await after.startLiveIfDue(now: pickupAt);
    // Idempotent: a second tick must not start a second trip.
    await after.startLiveIfDue(now: pickupAt);
    expect(after.byId(id)!.status, ReservationStatus.driverArrived);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(after.byId(id)!.status, ReservationStatus.inProgress);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(after.byId(id)!.status, ReservationStatus.completed);
    expect(after.upcoming(), isEmpty);
    after.dispose();
  });

  testWidgets('dispose cancels pending mock trip steps', (tester) async {
    final c = controller(
      dispatch: MockReservationDispatch(
        arriveAfter: const Duration(seconds: 5),
      ),
    );
    final id = await schedule(c);
    await c.startLiveIfDue(now: pickupAt.subtract(const Duration(minutes: 2)));
    expect(c.byId(id)!.status, ReservationStatus.driverEnRoute);
    c.dispose();
    await tester.pump(const Duration(seconds: 10));
    expect(c.byId(id)!.status, ReservationStatus.driverEnRoute);
  });
}

class _NobodyDispatch implements ReservationDispatch {
  @override
  Duration get assignmentLead => const Duration(minutes: 30);

  @override
  Duration? get acceptAfterBooking => null;

  @override
  ReservationDriver? driverFor(Reservation ride) => null;

  @override
  ReservationDriver? handoverFor(Reservation ride, DateTime now) => null;

  @override
  void driveTrip(
    String reservationId,
    ReservationStatus current,
    ReservationStepWriter writeStep,
  ) {}

  @override
  void dispose() {}
}

class _CountingDispatch extends _NobodyDispatch {
  int asked = 0;

  @override
  ReservationDriver? driverFor(Reservation ride) {
    asked += 1;
    return const ReservationDriver(firstName: 'Nope');
  }
}
