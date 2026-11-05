import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/ride_booking/data/api_quote_repository.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/quote.dart';

/// FIX JOB 7 (contract v0.18.30, `contract.json#smallFixes`).
Map<String, dynamic> _quote({Object? pickupAt}) => {
  'quoteId': 'qte_1',
  'categoryId': 'economy',
  'total': {'amountMinor': 21700, 'currency': 'SEK'},
  'fareLines': <Object>[],
  'expiresAt': '2026-11-05T10:05:00Z',
  'pickup': {'lat': 59.33, 'lng': 18.06},
  'dropoff': {'lat': 59.31, 'lng': 18.07},
  'stops': <Object>[],
  'pickupAt': pickupAt,
};

void main() {
  test(
    'Quote.pickupAt: a booked quote carries its pickup time, a live one none (owner Q8)',
    () {
      final booked = ApiQuoteRepository.contractQuoteOf(
        _quote(pickupAt: '2026-11-06T08:30:00Z'),
      )!;
      expect(booked.pickupAt, DateTime.utc(2026, 11, 6, 8, 30));
      final live = ApiQuoteRepository.contractQuoteOf(_quote())!;
      expect(live.pickupAt, isNull);
    },
  );

  test(
    'pickup ≈ drop-off is a warning, the quote stays bookable (owner Q9)',
    () {
      final warning = SamePointWarning.fromQuoteList([
        {'reason': 'same_pickup_dropoff', 'meters': 35, 'limitMeters': 100},
      ]);
      expect(warning?.meters, 35);
      expect(warning?.limitMeters, 100);
      final quote = ApiQuoteRepository.contractQuoteOf(
        _quote(),
        samePointWarning: warning,
      )!;
      expect(quote.samePointWarning, same(warning));
      expect(quote.bookable, isTrue);
      expect(SamePointWarning.fromQuoteList(null), isNull);
      expect(
        SamePointWarning.fromQuoteList([
          {'reason': 'other'},
        ]),
        isNull,
      );
    },
  );
}
