import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/config/rider_app_config.dart';
import 'package:movera_rider/core/contracts/cancel_fee.dart';
import 'package:movera_rider/core/contracts/money.dart';

import 'contract_fixtures.dart';

/// X1: the Rider reads `RiderAppConfig` (CONTRACT.md §6) as the Admin app
/// exports it. The three documents under `test/fixtures/admin_config/` are
/// copies of Admin's `webapp/src/config/__fixtures__/rider_app_config.*`.
Map<String, dynamic> _adminExport(String zone) =>
    jsonDecode(
          utf8.decode(
            File(
              'test/fixtures/admin_config/rider_app_config.$zone.json',
            ).readAsBytesSync(),
          ),
        )
        as Map<String, dynamic>;

void main() {
  group('Admin export', () {
    for (final (zone, currency, timeZone) in const [
      ('Z001', 'SEK', 'Europe/Stockholm'),
      ('FR-PC', 'EUR', 'Europe/Paris'),
      ('TN-TC', 'TND', 'Africa/Tunis'),
    ]) {
      test('$zone parses every §6 section', () {
        final config = RiderAppConfig.fromJson(_adminExport(zone))!;
        expect(config.zoneId, zone);
        expect(config.currency, currency);
        expect(config.timeZone, timeZone);
        expect(config.publishedAt, DateTime.utc(2026, 10, 19, 8));
        expect(config.categories.map((c) => c.id), [
          'economy',
          'comfort',
          'premium',
          'priority',
          'xl',
          'electric',
          'pet',
          'child_seat',
        ]);
        expect(config.categories.firstWhere((c) => c.id == 'xl').seats, 6);
        expect(config.feature('scheduledRides'), isTrue);
        expect(config.feature('somethingNotPublished'), isFalse);
        expect(config.paymentMethods, contains('card'));
        expect(config.maxStops, 3);
        expect(config.bookingHorizonDays, 7);
        expect(config.cancelReasons, hasLength(8));
        expect(config.minimumAppVersion, '1.0.0');
        // Every category has a live and a reservation rule in the zone's
        // currency.
        for (final category in config.categories) {
          expect(config.liveFeeFor(category.id), isNotNull);
          expect(config.reservationFeeFor(category.id), isNotNull);
        }
        expect(config.waiting!.perMin.currency, currency);
        expect(config.waiting!.noShowFee.currency, currency);
      });
    }

    test('TN-TC money keeps the 3-decimal exponent', () {
      final config = RiderAppConfig.fromJson(_adminExport('TN-TC'))!;
      final economy = config.liveFeeFor('economy')!;
      expect(economy.type, FeeType.fixed);
      expect(economy.value, 10500);
      expect(
        Money(economy.value.toInt(), config.currency).majorString,
        '10.500',
      );
      final premium = config.reservationFeeFor('premium')!;
      expect(premium.min, const Money(24000, 'TND'));
      // 25% of a 300.000 DT fare, inside the free window: 75.000 DT.
      expect(
        CancelFeeCalculator.reservation(
          premium,
          Money.fromLegacyMajor(300, 'TND'),
          90,
        ),
        const Money(75000, 'TND'),
      );
      expect(config.waiting!.noShowFee.majorString, '19.500');
    });

    test('a SEK seed never fills a TND document', () {
      final document = _adminExport('TN-TC')
        ..remove('waiting')
        ..['cancelFees'] = {'live': <String, Object>{}};
      final config = RiderAppConfig.fromJson(
        document,
        fallback: SeedRiderConfigRepository.seed,
      )!;
      expect(config.liveFeeFor('economy'), isNull);
      expect(config.reservationFeeFor('economy'), isNull);
      expect(config.waiting, isNull);
      // Currency-free fields still fall back.
      expect(config.timeZone, 'Africa/Tunis');
    });
  });

  group('safe defaults', () {
    test('missing sections take the fallback, then built-in defaults', () {
      final bare = RiderAppConfig.fromJson({'version': 3, 'currency': 'SEK'})!;
      expect(bare.timeZone, RiderAppConfig.defaultTimeZone);
      expect(bare.maxStops, RiderAppConfig.defaultMaxStops);
      expect(bare.categories, isEmpty);
      expect(bare.feature('wallet'), isFalse);
      expect(bare.waiting, isNull);
      expect(bare.liveCancelFees, isEmpty);

      final seeded = RiderAppConfig.fromJson({
        'version': 13,
        'currency': 'SEK',
      }, fallback: SeedRiderConfigRepository.seed)!;
      expect(seeded.zoneId, 'Z001');
      expect(seeded.categories, hasLength(5));
      expect(seeded.waiting!.noShowFee, const Money(5000));
      expect(seeded.reservationFeeFor('premium')!.freeMin, 120);
    });

    test('wrong types and unknown keys never throw', () {
      final config = RiderAppConfig.fromJson({
        'version': 4,
        'currency': 'EUR',
        'zoneId': 42,
        'timeZone': ['x'],
        'catalog': {
          'categories': [
            'economy',
            {'id': 'Not An Id'},
            {'id': 'comfort', 'seats': '4', 'sort': 'a'},
            {'id': 'comfort', 'label': 'duplicate'},
          ],
        },
        'features': {'wallet': 'yes', 'pin': true},
        'paymentMethods': 'card',
        'booking': {'maxStops': -1, 'bookingHorizonDays': 1.5},
        'cancelFees': {
          'live': {
            'economy': {'freeMin': 2, 'type': 'fixed', 'value': 300},
            'comfort': {
              'freeMin': 2,
              'type': 'percent',
              'value': 10,
              'min': {'amountMinor': 100, 'currency': 'SEK'},
            },
            'BAD': {'freeMin': 2, 'type': 'fixed', 'value': 1},
          },
          'reservation': 'none',
        },
        'waiting': {'freeWaitMin': 2, 'perMin': 5},
        'cancelReasons': [
          {'code': 'admin_fraud', 'title': 'Not for riders'},
          {'code': 'plans_changed', 'title': 'Plans changed'},
          {'code': 'something_else'},
        ],
        'rideCheck': {
          'stopMinutes': 2,
          'nested': {'a': 1},
        },
        'appUpdate': 'soon',
        'futureSection': {'anything': true},
      })!;
      expect(config.zoneId, '');
      expect(config.timeZone, RiderAppConfig.defaultTimeZone);
      expect(config.categories.single.id, 'comfort');
      expect(config.categories.single.seats, 4);
      expect(config.features, {'pin': true});
      // Not a list: the contract's four zone methods (owner Q7).
      expect(config.paymentMethods, ZoneDefaults.paymentMethods);
      expect(config.maxStops, RiderAppConfig.defaultMaxStops);
      expect(
        config.bookingHorizonDays,
        RiderAppConfig.defaultBookingHorizonDays,
      );
      expect(config.liveFeeFor('economy')!.value, 300);
      // A bound in another currency is not this zone's rule.
      expect(config.liveFeeFor('comfort'), isNull);
      expect(config.reservationCancelFees, isEmpty);
      expect(config.waiting, isNull);
      expect(config.cancelReasons.map((r) => r.code), ['plans_changed']);
      expect(config.rideCheck, {'stopMinutes': 2});
      expect(config.minimumAppVersion, isNull);
    });

    test('not a config document: null, so the last good one stays', () {
      expect(RiderAppConfig.fromJson(null), isNull);
      expect(RiderAppConfig.fromJson('{}'), isNull);
      expect(
        RiderAppConfig.fromJson({'version': '12', 'currency': 'SEK'}),
        isNull,
      );
      expect(
        RiderAppConfig.fromJson({'version': 12, 'currency': 'sek'}),
        isNull,
      );
    });
  });

  test('the seed equals the contract fixture in every section', () {
    final fixture = RiderAppConfig.fromJson(
      contractJson('fixtures/config/rider_app_config.json'),
    )!;
    final seed = SeedRiderConfigRepository.seed;
    expect(seed.timeZone, fixture.timeZone);
    expect(seed.publishedAt, fixture.publishedAt);
    expect(
      seed.categories.map((c) => '${c.id}/${c.label}/${c.seats}/${c.sort}'),
      fixture.categories.map((c) => '${c.id}/${c.label}/${c.seats}/${c.sort}'),
    );
    expect(seed.features, fixture.features);
    expect(seed.paymentMethods, fixture.paymentMethods);
    expect(seed.maxStops, fixture.maxStops);
    expect(seed.bookingHorizonDays, fixture.bookingHorizonDays);
    expect(seed.waiting!.perMin, fixture.waiting!.perMin);
    expect(seed.waiting!.noShowFee, fixture.waiting!.noShowFee);
    expect(seed.waiting!.freeWaitMin, fixture.waiting!.freeWaitMin);
    expect(seed.waiting!.noShowAfterMin, fixture.waiting!.noShowAfterMin);
    expect(seed.waiting!.byCategory.keys, fixture.waiting!.byCategory.keys);
    for (final id in fixture.waiting!.byCategory.keys) {
      final a = seed.waiting!.forCategory(id);
      final b = fixture.waiting!.forCategory(id);
      expect(
        [a.freeWaitMin, a.noShowAfterMin, a.perMin, a.noShowFee],
        [b.freeWaitMin, b.noShowAfterMin, b.perMin, b.noShowFee],
        reason: id,
      );
    }
    expect(seed.country, fixture.country);
    expect(seed.languages, fixture.languages);
    expect(seed.tips, fixture.tips);
    expect(seed.raiseSteps, fixture.raiseSteps);
    expect(seed.promoCap, fixture.promoCap);
    expect(seed.walletUsedFirst, fixture.walletUsedFirst);
    expect(seed.maxPickupMoveMeters, fixture.maxPickupMoveMeters);
    expect(
      seed.cancelReasons.map((r) => '${r.code}:${r.title}'),
      fixture.cancelReasons.map((r) => '${r.code}:${r.title}'),
    );
    expect(seed.rideCheck, fixture.rideCheck);
    expect(seed.latestAppVersion, fixture.latestAppVersion);
  });
}
