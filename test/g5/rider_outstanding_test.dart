import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/features/profile/domain/rider_outstanding.dart';

/// Driver group 5 Q3 (contract v0.18.7 `pickupWaiting.debtByCurrency`): an
/// owed cash fee is charged again only on a trip in the SAME currency. The
/// rider app shows what is owed per currency and never adds currencies up.
void main() {
  test(
    'the rider view of the fixture: oldest currency first, every currency listed',
    () async {
      final text = await File(
        'contracts/fixtures/pickup_waiting.json',
      ).readAsString();
      final cases =
          (jsonDecode(text) as Map<String, dynamic>)['debtByCurrency']
              as List<dynamic>;
      final withView =
          cases.firstWhere((c) => (c as Map)['riderView'] != null)
              as Map<String, dynamic>;
      final view = withView['riderView'] as Map<String, dynamic>;
      final owed = RiderOutstanding.fromRider(view);
      expect(owed.owesAnything, isTrue);
      expect(owed.byCurrency, [
        const Money(10000, 'SEK'),
        const Money(500, 'EUR'),
      ]);
      // Only the matching currency is ever shown with a quote.
      expect(owed.inCurrency('EUR'), const Money(500, 'EUR'));
      expect(owed.inCurrency('SEK'), const Money(10000, 'SEK'));
      expect(owed.inCurrency('TND'), isNull);
    },
  );

  test('a Swedish debt never shows on a Paris quote', () {
    final owed = RiderOutstanding.fromRider({
      'outstanding': {'amountMinor': 10000, 'currency': 'SEK'},
      'outstandingByCurrency': [
        {'amountMinor': 10000, 'currency': 'SEK'},
      ],
    });
    expect(owed.inCurrency('EUR'), isNull);
    expect(owed.inCurrency('SEK'), const Money(10000, 'SEK'));
  });

  test('an older server with only `outstanding` is still read', () {
    final owed = RiderOutstanding.fromRider({
      'outstanding': {'amountMinor': 3500, 'currency': 'SEK'},
    });
    expect(owed.byCurrency, [const Money(3500, 'SEK')]);
  });

  test('nothing owed: null, missing or zero', () {
    expect(RiderOutstanding.fromRider({}).owesAnything, isFalse);
    expect(
      RiderOutstanding.fromRider({'outstanding': null}).owesAnything,
      isFalse,
    );
    expect(
      RiderOutstanding.fromRider({
        'outstandingByCurrency': [
          {'amountMinor': 0, 'currency': 'SEK'},
        ],
      }).owesAnything,
      isFalse,
    );
  });
}
