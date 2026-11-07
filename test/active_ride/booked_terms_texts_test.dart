import 'package:flutter/widgets.dart';
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
      "driver's arrival if that is later",
    );
  });

  test('live ride: unchanged', () {
    final lines = TripTermsLines.fromTerms(terms).lines;
    final l = L10n.current;
    expect(lines, contains(l.termsCancelAfterArrived));
    expect(lines, isNot(contains(l.termsBookedCancelAfterArrived)));
  });

  // Contract d19a8a8 (0.18.51) words, verbatim (a straight ' in English).
  for (final (lang, included, noShow, cancel, before) in [
    (
      'sv',
      "{minutes} min gratis väntan räknas från upphämtningstiden, eller från när föraren kommer fram om det är senare",
      "Bokad resa: om du inte kommer inom {noShowAfter} min efter förarens ankomst eller upphämtningstiden (det som är senast) tas en avgift på {noShowFee} ut",
      "Bokad resa: avbokning efter att föraren kommit fram kostar avbokningsavgiften för bokade resor",
      "Före upphämtningstiden",
    ),
    (
      'fr',
      "{minutes} min d’attente gratuite comptées à partir de l’heure de prise en charge, ou de l’arrivée du chauffeur si elle est plus tardive",
      "Course programmée : si vous n’êtes pas là {noShowAfter} min après l’arrivée du chauffeur ou l’heure de prise en charge (la plus tardive des deux), des frais de {noShowFee} s’appliquent",
      "Course programmée : une annulation après l’arrivée du chauffeur coûte les frais d’annulation de la réservation",
      "Avant l’heure de prise en charge",
    ),
    (
      'en',
      "{minutes} min free waiting, counted from the pickup time, or from the driver's arrival if that is later",
      "Booked ride: if you do not show up within {noShowAfter} min after the later of the driver's arrival and the pickup time, a {noShowFee} fee applies",
      "Booked ride: cancelling after the driver has arrived costs the booked-ride cancel fee",
      "Before the pickup time",
    ),
  ]) {
    test('$lang texts are the contract words, character for character', () {
      final l = lookupAppLocalizations(Locale(lang));
      expect(l.termsBookedIncludedWaiting('{minutes}'), included);
      expect(l.termsBookedNoShow('{noShowAfter}', '{noShowFee}'), noShow);
      expect(l.termsBookedCancelAfterArrived, cancel);
      expect(l.waitingBeforePickup, before);
    });
  }
}
