import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/ride_booking/data/api_quote_repository.dart';

/// v0.18.163 (contract.json#liveTraffic.rider; owner 2026-11-25 "Google
/// trafic réel"): the rider shows the server's `Quote.tripSeconds` (live
/// traffic), not its own straight-line minutes; no placeholder 600 s.
Map<String, dynamic> get _contract =>
    jsonDecode(File('contracts/contract.json').readAsStringSync())
        as Map<String, dynamic>;

Map<String, dynamic> _quote({Object? tripSeconds}) => {
  'quoteId': 'qte_lt163',
  'categoryId': 'economy',
  'total': {'amountMinor': 21700, 'currency': 'SEK'},
  'fareLines': <Object>[],
  'expiresAt': '2099-01-01T00:00:00Z',
  'pickup': {'lat': 59.33, 'lng': 18.06},
  'dropoff': {'lat': 59.31, 'lng': 18.07},
  'stops': <Object>[],
  if (tripSeconds != null) 'tripSeconds': tripSeconds,
};

int? _minutes(Object? tripSeconds) => ApiQuoteRepository.contractQuoteOf(
  _quote(tripSeconds: tripSeconds),
)!.tripMinutes;

void main() {
  test('the contract says the rider shows Quote.tripSeconds', () {
    final lt = _contract['liveTraffic'] as Map<String, dynamic>;
    expect(lt['rider'] as String, contains('Quote.tripSeconds'));
  });

  test('tripSeconds 1560 is 26 minutes (Google Maps 26, not 13)', () {
    final quote = ApiQuoteRepository.contractQuoteOf(
      _quote(tripSeconds: 1560),
    )!;
    expect(quote.tripSeconds, 1560);
    expect(quote.tripMinutes, 26);
  });

  test('an older server or a bad value: null, the app estimates', () {
    expect(_minutes(null), isNull);
    expect(_minutes(-5), isNull);
  });

  test('a few seconds round up to one minute', () {
    expect(_minutes(20), 1);
  });
}
