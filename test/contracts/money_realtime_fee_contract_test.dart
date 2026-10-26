import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/config/rider_app_config.dart';
import 'package:movera_rider/core/contracts/cancel_fee.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/contracts/trip_status.dart';
import 'package:movera_rider/core/realtime/realtime_gate.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';
import 'package:movera_rider/features/reservations/domain/scheduled_ride_rules.dart';

import 'contract_fixtures.dart';

/// Contract v0.3.0: money, the realtime gate and the rider cancel fee,
/// replayed from the shipped fixtures with the reference engine's answers.
void main() {
  group('fixtures/money.json', () {
    final fixture =
        contractJson('fixtures/money.json')! as Map<String, dynamic>;

    test('exponents equal contract.json#currencies', () {
      final currencies = contract['currencies'] as Map<String, dynamic>;
      expect({
        for (final e in currencies.entries) e.key: e.value['exponent'],
      }, Money.exponents);
    });

    test('valid cases parse and render with the ISO exponent', () {
      for (final row in fixture['cases'] as List) {
        final money = Money.fromWire(row['money']);
        expect(money, isNotNull, reason: '${row['money']}');
        expect(money!.majorString, row['major'], reason: '${row['money']}');
        expect(money.toJson(), row['money']);
      }
    });

    test('invalid cases are not Money', () {
      for (final raw in fixture['invalid'] as List) {
        expect(Money.fromWire(raw), isNull, reason: '$raw');
      }
    });
  });

  test('fixtures/events.json: the gate gives identical dispositions', () {
    final realtime = contract['realtime'] as Map<String, dynamic>;
    expect(
      RealtimeKind.values.map((k) => k.wireName).toList(),
      List<String>.from(realtime['kinds'] as List),
    );
    expect({
      for (final k in RealtimeKind.values)
        if (k.passesAfterTerminal) k.wireName,
    }, Set<String>.from(realtime['afterTerminal'] as List));
    final fixture =
        contractJson('fixtures/events.json')! as Map<String, dynamic>;
    for (final scenario in fixture['cases'] as List) {
      final gate = RealtimeGate();
      for (final event in scenario['events'] as List) {
        final projection = event['projection'];
        final status = TripStatusWire.parse(
          event['status'] ?? (projection is Map ? projection['status'] : null),
        );
        final got = gate.admit(
          eventId: event['eventId'] as String,
          tripId: event['tripId'] as String,
          sequence: event['sequence'] as int,
          kind: RealtimeKindWire.parse(event['kind'])!,
          isTerminalStatus: status?.isTerminal ?? false,
        );
        expect(
          got.wireName,
          event['expect'],
          reason: '${scenario['id']} ${event['eventId']}',
        );
      }
    }
  });

  group('fixtures/cancel_fees.json', () {
    test('the calculator matches every case', () {
      final fixture =
          contractJson('fixtures/cancel_fees.json')! as Map<String, dynamic>;
      for (final row in fixture['cases'] as List) {
        final rule = FeeRule.fromJson(row['rule'])!;
        final fare = Money.fromWire(row['fare'])!;
        final fee = row['kind'] == 'live'
            ? CancelFeeCalculator.live(
                rule,
                fare,
                row['minutesSinceAccept'] as int,
              )
            : CancelFeeCalculator.reservation(
                rule,
                fare,
                row['minutesBeforePickup'] as int,
              );
        expect(fee, Money.fromWire(row['fee']), reason: '${row['id']}');
      }
    });

    test('scheduled rides use the same calculator (free at the window)', () {
      const rules = ScheduledRideRules(
        freeCancelMinutesBeforePickup: 60,
        lateCancelFee: Money(5000),
      );
      final pickup = DateTime.utc(2026, 10, 20, 12);
      Reservation ride() => Reservation(
        reservationId: 'r1',
        createdAt: DateTime.utc(2026, 10, 19),
        scheduledPickupAt: pickup,
        pickup: const ReservationPlace(label: 'A'),
        destination: const ReservationPlace(label: 'B'),
        categoryId: 'economy',
        categoryName: 'Movera',
        categoryImage: '',
        passengerCount: 1,
        price: 259,
        currency: 'SEK',
        paymentMethod: 'cash',
        status: ReservationStatus.driverAssigned,
      );
      expect(
        rules
            .cancelTermsFor(
              ride(),
              pickup.subtract(const Duration(minutes: 61)),
            )
            .fee,
        isNull,
      );
      expect(
        rules
            .cancelTermsFor(
              ride(),
              pickup.subtract(const Duration(minutes: 30)),
            )
            .fee,
        const Money(5000),
      );
    });
  });

  group('RiderAppConfig cancelFees', () {
    final document =
        contractJson('fixtures/config/rider_app_config.json')!
            as Map<String, dynamic>;

    test('parses the published document', () {
      final config = RiderAppConfig.fromJson(document)!;
      expect(config.version, 12);
      expect(config.currency, 'SEK');
      final premium = config.liveFeeFor('premium')!;
      expect(premium.type, FeeType.percent);
      expect(premium.min, const Money(5000));
      // movera is read as economy.
      expect(config.liveFeeFor('movera')!.value, 3500);
      expect(config.reservationFeeFor('xl')!.freeMin, 120);
    });

    test('the local seed equals the fixture', () {
      final fixture = RiderAppConfig.fromJson(document)!;
      final seed = SeedRiderConfigRepository.seed;
      String dump(Map<String, FeeRule> rules) =>
          '${{for (final e in rules.entries) e.key: e.value.toJson()}}';
      expect(dump(seed.liveCancelFees), dump(fixture.liveCancelFees));
      expect(
        dump(seed.reservationCancelFees),
        dump(fixture.reservationCancelFees),
      );
    });

    test('a bad rule keeps the seed, unknown keys are ignored', () {
      final config = RiderAppConfig.fromJson({
        'version': 13,
        'currency': 'SEK',
        'somethingNew': true,
        'cancelFees': {
          'live': {
            'economy': {'freeMin': -1, 'type': 'fixed', 'value': 1},
          },
        },
      }, fallback: SeedRiderConfigRepository.seed)!;
      expect(config.liveFeeFor('economy')!.value, 3500);
    });

    test('live preview: free inside the window, then the fee', () {
      final config = SeedRiderConfigRepository.seed;
      final accepted = DateTime.utc(2026, 10, 19, 8);
      LiveCancelFeePreview at(int minutes) => LiveCancelFeePreview.of(
        config,
        categoryId: 'economy',
        fare: const Money(25900),
        acceptedAt: accepted,
        now: accepted.add(Duration(minutes: minutes)),
      )!;
      expect(at(1).fee, const Money(0));
      expect(at(1).freeMinutesLeft, 1);
      expect(at(2).fee, const Money(3500));
    });
  });
}
