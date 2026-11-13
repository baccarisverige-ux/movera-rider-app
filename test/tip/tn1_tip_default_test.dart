import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/config/rider_app_config.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/shared/formatters/money.dart';

/// TN-1 (contract v0.18.82 `configDefaults.tipRules.customMax`, owner
/// Q-S5-6 2026-11-13 "Yes, 30 DT"; audits/impact/contracts-0.18.82-s5j3.md
/// :113): the largest typed tip when the zone document has none is the
/// contract default of the country (SE 200 kr, FR 20 €, TN 30 DT). Before
/// this every non-SEK currency got 2000 minor units, so Tunisia got
/// 2.000 DT instead of 30.000 DT.
Money? money(Object? raw) => raw is Map
    ? Money(raw['amountMinor'] as int, raw['currency'] as String)
    : null;

void main() {
  test('TN-1: the Tunisian default is 30.000 DT (30000 millimes)', () {
    final tn = TipRules.forCountry('TN', 'TND').customMax!;
    expect(tn, const Money(30000, 'TND'));
    expect(formatMoney(tn), contains('30.000'));
  });

  test('TN-1: the finish screen fallback (currency only) gives 30 DT', () {
    final rules = TipRules.forCountry(ZoneDefaults.countryOf('TND'), 'TND');
    expect(rules.customMax, const Money(30000, 'TND'));
  });

  test('TN-1: SE 200 kr and FR 20 € stay as they were', () {
    expect(TipRules.forCountry('SE', 'SEK').customMax, const Money(20000));
    expect(
      TipRules.forCountry('FR', 'EUR').customMax,
      const Money(2000, 'EUR'),
    );
  });

  test('TN-1: a zone document without customMax reads the country default', () {
    final rules = TipRules.read({'customAmount': true}, money, 'TN')!;
    expect(rules.customAmount, isTrue);
    expect(rules.customMax, const Money(30000, 'TND'));
  });

  test('TN-1: a wrong-currency customMax reads the country default', () {
    final rules = TipRules.read(
      {
        'customAmount': true,
        'customMax': {'amountMinor': 2000, 'currency': 'EUR'},
      },
      money,
      'TN',
    )!;
    expect(rules.customMax, const Money(30000, 'TND'));
  });

  test('TN-1: a served customMax is kept (the admin setting wins)', () {
    final rules = TipRules.read(
      {
        'customAmount': true,
        'customMax': {'amountMinor': 45000, 'currency': 'TND'},
      },
      money,
      'TN',
    )!;
    expect(rules.customMax, const Money(45000, 'TND'));
  });

  test(
    'TN-1: the app defaults equal the contract copy, country by country',
    () {
      final contract =
          jsonDecode(File('contracts/contract.json').readAsStringSync())
              as Map<String, dynamic>;
      final defaults =
          (contract['configDefaults'] as Map)['tipRules']
              as Map<String, dynamic>;
      final byCountry = defaults['customMax'] as Map<String, dynamic>;
      expect(byCountry.keys, containsAll(<String>['SE', 'FR']));
      for (final entry in byCountry.entries) {
        final want = money(entry.value)!;
        expect(
          TipRules.forCountry(entry.key, want.currency).customMax,
          want,
          reason: entry.key,
        );
      }
    },
  );
}
