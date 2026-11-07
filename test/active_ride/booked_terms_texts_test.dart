import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/contracts/trip_terms.dart';
import 'package:movera_rider/features/active_ride/presentation/trip_terms_note.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Contract v0.18.51 §73 (apps.riderApp): a booked ride's terms say the
/// free waiting counts from the later of the pickup time and the driver's
/// arrival (bookLater.texts.includedWaiting), its own no-show words
/// (texts.noShow) and that a cancel after arrival costs the booked-ride
/// cancel fee (texts.cancelAfterArrived), never "counts as a no-show".
void main() {
  final terms = TripTerms.fromWire({
    'currency': 'SEK',
    'freeWaitMin': 15,
    'waitPerMin': {'amountMinor': 500, 'currency': 'SEK'},
    'noShowAfterMin': 10,
    'noShowFee': {'amountMinor': 6500, 'currency': 'SEK'},
    'noShowDriverSharePct': 80,
    'cancelDriverSharePct': 50,
    'cancelAfterArrivedIsNoShow': true,
    'maxPickupMoveMeters': 200,
  })!;

  test('booked ride: the §73 texts', () {
    final lines = TripTermsLines.fromTerms(terms, booked: true).lines;
    final l = L10n.current;
    expect(lines, contains(l.termsBookedIncludedWaiting('15')));
    expect(
      lines.where((x) => x.startsWith('Booked ride: if you do not show up')),
      hasLength(1),
    );
    expect(lines, contains(l.termsBookedCancelAfterArrived));
    expect(lines, isNot(contains(l.termsCancelAfterArrived)));
    expect(
      l.termsBookedIncludedWaiting('15'),
      '15 min free waiting, counted from the pickup time, or from the '
      'driver’s arrival if that is later',
    );
  });

  test('live ride: unchanged', () {
    final lines = TripTermsLines.fromTerms(terms).lines;
    final l = L10n.current;
    expect(lines, contains(l.termsCancelAfterArrived));
    expect(lines, isNot(contains(l.termsBookedCancelAfterArrived)));
  });
}
