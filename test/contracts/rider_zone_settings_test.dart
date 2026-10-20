import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/config/rider_app_config.dart';
import 'package:movera_rider/core/contracts/money.dart';

import 'contract_fixtures.dart';

/// Contract v0.4.0 per-zone settings in `RiderAppConfig` (CONTRACT.md §6,
/// owner round 2): tips, raise-offer steps, payment methods, wallet, promo
/// cap, pickup move limit, languages, country and waiting per category.
Map<String, dynamic> _adminExport(String zone) =>
    jsonDecode(
          utf8.decode(
            File(
              'test/fixtures/admin_config/rider_app_config.$zone.json',
            ).readAsBytesSync(),
          ),
        )
        as Map<String, dynamic>;

List<int> _minor(List<Money> amounts) => [for (final m in amounts) m.amountMinor];

void main() {
  test('ZoneDefaults equal contract.json#configDefaults', () {
    final defaults = contract['configDefaults'] as Map<String, dynamic>;
    expect(ZoneDefaults.maxStops, defaults['maxStops']);
    expect(ZoneDefaults.maxPickupMoveMeters, defaults['maxPickupMoveMeters']);
    expect(ZoneDefaults.freeWaitMin, defaults['freeWaitMin']['default']);
    expect(ZoneDefaults.freeWaitMinXl, defaults['freeWaitMin']['xl']);
    expect(
      ZoneDefaults.paymentMethods,
      contract['zonePaymentMethods']['values'],
    );
    expect(ZoneDefaults.languages, contract['languages']['values']);
    final countries = defaults['countries'] as Map<String, dynamic>;
    for (final MapEntry(key: country, value: row) in countries.entries) {
      final currency = row['currency'] as String;
      expect(ZoneDefaults.countryOf(currency), country);
      expect(ZoneDefaults.languageOf(country), row['defaultLanguage']);
      List<Money> wire(String key) => [
        for (final m in row[key] as List) Money.fromWire(m)!,
      ];
      expect(
        [for (final o in ZoneDefaults.tipsIn(currency)) o.amount],
        wire('tips'),
        reason: '$country tips',
      );
      expect(
        [for (final o in ZoneDefaults.raiseStepsIn(currency)) o.amount],
        wire('raiseSteps'),
        reason: '$country raise steps',
      );
    }
  });

  group('Admin export', () {
    for (final (zone, country, lang, tips, steps) in const [
      ('Z001', 'SE', 'sv', [1000, 2000, 3000], [5000, 10000, 15000, 20000]),
      ('FR-PC', 'FR', 'fr', [100, 200, 500], [200, 400, 600, 800]),
      ('TN-TC', 'TN', 'fr', [1000, 2000, 3000], [2000, 4000, 6000, 8000]),
    ]) {
      test('$zone reads every v0.4 field', () {
        final config = RiderAppConfig.fromJson(_adminExport(zone))!;
        expect(config.country, country);
        expect(config.languages.available, ['en', 'fr', 'sv']);
        expect(
          [config.languages.rider, config.languages.driver, config.languages.admin],
          [lang, lang, lang],
        );
        expect(config.paymentMethods, ['cash', 'card', 'apple_pay', 'google_pay']);
        expect(config.walletUsedFirst, isTrue);
        expect(_minor(config.enabledTips), tips);
        expect(_minor(config.enabledRaiseSteps), steps);
        expect(config.enabledTips.every((m) => m.currency == config.currency), isTrue);
        expect(config.promoCap, isNull);
        expect(config.maxStops, 3);
        expect(config.maxPickupMoveMeters, 500);
        final waiting = config.waiting!;
        expect(waiting.forCategory('xl').freeWaitMin, 3);
        expect(waiting.forCategory('economy').freeWaitMin, 5);
        expect(waiting.forCategory('movera').freeWaitMin, 5, reason: 'alias');
        for (final id in waiting.byCategory.keys) {
          final terms = waiting.forCategory(id);
          expect(terms.noShowAfterMin, terms.freeWaitMin, reason: '$id Q41');
          expect(terms.perMin.currency, config.currency);
        }
      });
    }
  });

  test('the contract sample reads the same as the seed', () {
    final sample = RiderAppConfig.fromJson(
      contractJson('fixtures/config/rider_app_config.json'),
    )!;
    expect(sample.country, 'SE');
    expect(_minor(sample.enabledTips), [1000, 2000, 3000]);
    expect(sample.paymentMethods, isNot(contains('swish')));
    expect(sample.waiting!.forCategory('xl').noShowAfterMin, 3);
  });

  group('safe defaults, never a crash', () {
    test('a v0.3 document gets the defaults of its currency', () {
      final config = RiderAppConfig.fromJson({'version': 1, 'currency': 'EUR'})!;
      expect(config.country, 'FR');
      expect(config.languages.rider, 'fr');
      expect(_minor(config.enabledTips), [100, 200, 500]);
      expect(_minor(config.enabledRaiseSteps), [200, 400, 600, 800]);
      expect(config.paymentMethods, ZoneDefaults.paymentMethods);
      expect(config.promoCap, isNull);
      expect(config.walletUsedFirst, isTrue);
      expect(config.maxPickupMoveMeters, 500);
    });

    test('v0.3 payment ids: aliases read, swish and wallet dropped', () {
      final config = RiderAppConfig.fromJson({
        'version': 1,
        'currency': 'SEK',
        'paymentMethods': ['card', 'swish', 'apple', 'google', 'wallet', 'cash', 'd17', 7],
      })!;
      expect(config.paymentMethods, ['card', 'apple_pay', 'google_pay', 'cash']);
      final onlySwish = RiderAppConfig.fromJson({
        'version': 1,
        'currency': 'SEK',
        'paymentMethods': ['swish'],
      })!;
      expect(onlySwish.paymentMethods, ZoneDefaults.paymentMethods);
    });

    test('bad values are skipped or fall back', () {
      final config = RiderAppConfig.fromJson({
        'version': 2,
        'currency': 'TND',
        'country': 'tunisia',
        'languages': {
          'available': ['ar', 'fr', 'en', 5],
          'default': {'rider': 'ar', 'driver': 'en', 'admin': null},
        },
        'tips': [
          {'amount': {'amountMinor': 1500, 'currency': 'TND'}, 'enabled': false},
          {'amount': {'amountMinor': 1500, 'currency': 'TND'}},
          {'amount': {'amountMinor': 500, 'currency': 'SEK'}},
          {'amount': {'amountMinor': -1, 'currency': 'TND'}},
          {'amount': 3},
          'x',
          {'amount': {'amountMinor': 2500, 'currency': 'TND'}, 'enabled': 'yes'},
        ],
        'raiseSteps': [
          {'amount': {'amountMinor': 200, 'currency': 'EUR'}},
        ],
        'promoCap': {'amountMinor': 5000, 'currency': 'EUR'},
        'wallet': {'usedFirst': 'no'},
        'booking': {'maxPickupMoveMeters': -5},
        'waiting': {
          'freeWaitMin': 5,
          'perMin': {'amountMinor': 3700, 'currency': 'TND'},
          'noShowAfterMin': 5,
          'noShowFee': {'amountMinor': 19500, 'currency': 'TND'},
          'byCategory': {
            'xl': {'perMin': {'amountMinor': 1, 'currency': 'SEK'}},
            'premium': {'freeWaitMin': 7},
            'BAD': {'freeWaitMin': 1},
            'comfort': 'none',
          },
        },
      })!;
      expect(config.country, 'TN', reason: 'from the currency');
      expect(config.languages.available, ['fr', 'en']);
      expect(config.languages.rider, 'fr', reason: 'ar is not an app language');
      expect(config.languages.driver, 'en');
      expect(config.languages.admin, 'fr');
      expect(config.tips, const [
        AmountOption(amount: Money(1500, 'TND'), enabled: false),
        AmountOption(amount: Money(2500, 'TND')),
      ]);
      expect(_minor(config.enabledTips), [2500]);
      expect(_minor(config.enabledRaiseSteps), [2000, 4000, 6000, 8000]);
      expect(config.promoCap, isNull, reason: 'another currency');
      expect(config.walletUsedFirst, isTrue);
      expect(config.maxPickupMoveMeters, 500);
      final waiting = config.waiting!;
      expect(waiting.byCategory.keys, unorderedEquals(['xl', 'premium']));
      expect(waiting.forCategory('xl').freeWaitMin, 3);
      expect(waiting.forCategory('xl').noShowAfterMin, 3);
      expect(waiting.forCategory('xl').perMin, const Money(3700, 'TND'));
      expect(waiting.forCategory('premium').noShowAfterMin, 7);
      expect(waiting.forCategory('comfort').freeWaitMin, 5, reason: 'top level');
    });

    test('a valid promo cap and an explicit null', () {
      final capped = RiderAppConfig.fromJson({
        'version': 1,
        'currency': 'SEK',
        'promoCap': {'amountMinor': 10000, 'currency': 'SEK'},
      })!;
      expect(capped.promoCap, const Money(10000));
      final none = RiderAppConfig.fromJson({
        'version': 2,
        'currency': 'SEK',
        'promoCap': null,
      }, fallback: capped)!;
      expect(none.promoCap, isNull);
      final kept = RiderAppConfig.fromJson({
        'version': 3,
        'currency': 'SEK',
      }, fallback: capped)!;
      expect(kept.promoCap, const Money(10000));
    });
  });
}
