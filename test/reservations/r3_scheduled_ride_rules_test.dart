import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/api_scheduled_ride_rules_source.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';
import 'package:movera_rider/features/reservations/domain/scheduled_ride_rules.dart';
import 'package:movera_rider/features/reservations/presentation/reservation_format.dart';

/// Round 3 Q11 / Q12 rider rules: the admin-set free-cancel window and late
/// fee, and when the rider sees the driver. Behavioural only.
void main() {
  final pickupAt = DateTime(2026, 10, 20, 8, 0);

  Reservation ride({
    ReservationStatus status = ReservationStatus.scheduled,
    ReservationDriver? driver,
  }) {
    return Reservation(
      reservationId: 'rsv_rules',
      createdAt: DateTime(2026, 10, 15, 9),
      scheduledPickupAt: pickupAt,
      pickup: const ReservationPlace(label: 'Stockholm Central'),
      destination: const ReservationPlace(label: 'Arlanda Airport'),
      categoryId: 'economy',
      categoryName: 'Movera',
      categoryImage: 'assets/images/rides/movera.webp',
      price: 459,
      paymentMethod: 'Visa •••• 4242',
      status: status,
      driver: driver,
    );
  }

  const elin = ReservationDriver(
    firstName: 'Elin',
    id: 'drv_mock_001',
    vehicle: 'Volvo XC40 Recharge',
    vehicleColor: 'Black',
    plate: 'MVR 204',
  );

  group('defaults mirror the admin defaults', () {
    test(
      'free until 1 h before pickup, then kr 50; driver shown on accept',
      () {
        const rules = ScheduledRideRules.defaults;
        expect(rules.freeCancelWindow, const Duration(hours: 1));
        expect(rules.lateCancelFee, const Money(5000, 'SEK'));
        expect(rules.showDriverOnAccept, isTrue);
      },
    );

    test('the mock API publishes the same defaults', () async {
      final source = ApiScheduledRideRulesSource(
        ApiClient(client: InProcessMockClient()),
      );
      expect(await source.fetch(), ScheduledRideRules.defaults);
    });
  });

  group('wire shape', () {
    test('reads every field and round-trips', () {
      final rules = ScheduledRideRules.fromJson({
        'freeCancelMinutesBeforePickup': 120,
        'lateCancelFeeMinor': 7500,
        'currency': 'sek',
        'showDriverOnAccept': false,
      });
      expect(rules.freeCancelMinutesBeforePickup, 120);
      expect(rules.lateCancelFee, const Money(7500, 'SEK'));
      expect(rules.showDriverOnAccept, isFalse);
      expect(ScheduledRideRules.fromJson(rules.toJson()), rules);
    });

    test('a missing or invalid field keeps the fallback value', () {
      final rules = ScheduledRideRules.fromJson({
        'freeCancelMinutesBeforePickup': -5,
        'lateCancelFeeMinor': 12.5,
        'currency': 'kronor',
      });
      expect(rules, ScheduledRideRules.defaults);
      expect(ScheduledRideRules.fromJson(null), ScheduledRideRules.defaults);
      expect(
        ScheduledRideRules.fromJson({
          'freeCancelMinutesBeforePickup':
              ScheduledRideRules.maxFreeCancelMinutes + 1,
        }).freeCancelMinutesBeforePickup,
        60,
      );
    });
  });

  group('cancel terms', () {
    const rules = ScheduledRideRules.defaults;

    test('free before the window closes, with the free-until time', () {
      final terms = rules.cancelTermsFor(
        ride(),
        pickupAt.subtract(const Duration(minutes: 61)),
      );
      expect(terms.isFree, isTrue);
      expect(terms.freeForNow, isTrue);
      expect(terms.freeUntil, DateTime(2026, 10, 20, 7, 0));
      expect(ReservationFormat.cancelTermsTitle(terms), contains('07:00'));
    });

    test('the fee applies from the moment the window closes', () {
      final atLine = rules.cancelTermsFor(ride(), DateTime(2026, 10, 20, 7, 0));
      expect(atLine.fee, const Money(5000));
      final late = rules.cancelTermsFor(
        ride(driver: elin, status: ReservationStatus.driverAssigned),
        pickupAt.subtract(const Duration(minutes: 20)),
      );
      expect(late.fee, const Money(5000));
      expect(
        ReservationFormat.cancelTermsTitle(late),
        'Cancellation fee: kr 50',
      );
      expect(ReservationFormat.cancelTermsBody(late), contains('07:00'));
    });

    test('a pickup time that passed without a driver is always free', () {
      final terms = rules.cancelTermsFor(
        ride(status: ReservationStatus.driverAssignmentPending),
        pickupAt.add(const Duration(minutes: 3)),
      );
      expect(terms.isFree, isTrue);
      expect(terms.freeForNow, isFalse);
      expect(ReservationFormat.cancelTermsTitle(terms), 'Free cancellation');
    });

    test('a zero fee means cancelling is always free', () {
      const free = ScheduledRideRules(lateCancelFee: Money(0));
      final terms = free.cancelTermsFor(
        ride(),
        pickupAt.subtract(const Duration(minutes: 5)),
      );
      expect(terms.isFree, isTrue);
      expect(
        ReservationFormat.cancellationSummary(terms),
        'Free to cancel at any time.',
      );
    });

    test('an admin window of 2 h moves the free-until time', () {
      const twoHours = ScheduledRideRules(freeCancelMinutesBeforePickup: 120);
      final terms = twoHours.cancelTermsFor(
        ride(),
        pickupAt.subtract(const Duration(minutes: 90)),
      );
      expect(terms.fee, const Money(5000));
      expect(ReservationFormat.window(terms.window), '2 h');
    });
  });

  group('driver reveal', () {
    test(
      'shown once a driver accepts; admin switch off waits for the road',
      () {
        final assigned = ride(
          driver: elin,
          status: ReservationStatus.driverAssigned,
        );
        final enRoute = ride(
          driver: elin,
          status: ReservationStatus.driverEnRoute,
        );
        const off = ScheduledRideRules(showDriverOnAccept: false);
        expect(ScheduledRideRules.defaults.showsDriverOf(assigned), isTrue);
        expect(off.showsDriverOf(assigned), isFalse);
        expect(off.showsDriverOf(enRoute), isTrue);
        expect(ScheduledRideRules.defaults.showsDriverOf(ride()), isFalse);
      },
    );

    test('the car reads with its colour', () {
      expect(elin.carLabel, 'Black Volvo XC40 Recharge');
      expect(const ReservationDriver(firstName: 'A').carLabel, isNull);
    });
  });

  group('controller', () {
    ReservationController controller(ScheduledRideRulesSource? source) {
      return ReservationController(
        store: LocalReservationRepository(storage: MemoryReservationStorage()),
        rulesSource: source,
      );
    }

    test('refreshRules takes what admin published in the mock API', () async {
      final mock = InProcessMockClient();
      mock.scheduledRideRules
        ..['freeCancelMinutesBeforePickup'] = 90
        ..['lateCancelFeeMinor'] = 7500;
      final c = controller(
        ApiScheduledRideRulesSource(ApiClient(client: mock)),
      );
      var notified = 0;
      c.addListener(() => notified += 1);

      await c.refreshRules();

      expect(c.rules.freeCancelWindow, const Duration(minutes: 90));
      expect(c.rules.lateCancelFee, const Money(7500));
      expect(notified, 1);
      // The same answer again is not a change.
      await c.refreshRules();
      expect(notified, 1);
    });

    test('a server error reads as no answer', () async {
      final mock = InProcessMockClient()..failNext = true;
      final source = ApiScheduledRideRulesSource(ApiClient(client: mock));
      expect(await source.fetch(), isNull);
    });

    test('a failed read keeps the rules already held', () async {
      const held = ScheduledRideRules(freeCancelMinutesBeforePickup: 30);
      for (final source in [_NoAnswer(), _Throws()]) {
        final c = ReservationController(
          store: LocalReservationRepository(
            storage: MemoryReservationStorage(),
          ),
          rulesSource: source,
          rules: held,
        );
        await c.refreshRules();
        expect(c.rules, held);
      }
    });

    test('without a source the defaults stay', () async {
      final c = controller(null);
      await c.refreshRules();
      expect(c.rules, ScheduledRideRules.defaults);
    });
  });
}

class _NoAnswer implements ScheduledRideRulesSource {
  @override
  Future<ScheduledRideRules?> fetch() async => null;
}

class _Throws implements ScheduledRideRulesSource {
  @override
  Future<ScheduledRideRules?> fetch() async => throw StateError('offline');
}
