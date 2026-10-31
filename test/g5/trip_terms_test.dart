import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/config/rider_app_config.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/contracts/trip_terms.dart';
import 'package:movera_rider/features/active_ride/presentation/trip_terms_note.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Driver group 5 (contract v0.18.7 `pickupWaiting.terms`): every waiting
/// and cancel number the rider reads comes from the trip's `terms` (or the
/// zone's served config), in the trip's currency. Nothing is hard-coded:
/// a Paris trip reads euro terms, a Stockholm trip kronor.
void main() {
  Map<String, Object?> parisTerms() => {
    'currency': 'EUR',
    'freeWaitMin': 3,
    'waitPerMin': {'amountMinor': 110, 'currency': 'EUR'},
    'noShowAfterMin': 3,
    'noShowFee': {'amountMinor': 800, 'currency': 'EUR'},
    'noShowDriverSharePct': 80,
    'cancelRule': {
      'freeMin': 2,
      'type': 'fixed',
      'value': 500,
      'min': null,
      'max': null,
    },
    'cancelDriverSharePct': 80,
    'cancelAfterArrivedIsNoShow': true,
    'maxPickupMoveMeters': 200,
  };

  tearDown(() => L10n.use('en'));

  test('TripTerms reads the wire shape in the trip currency', () {
    final terms = TripTerms.fromWire(parisTerms());
    expect(terms, isNotNull);
    expect(terms!.currency, 'EUR');
    expect(terms.waitPerMin, const Money(110, 'EUR'));
    expect(terms.noShowFee, const Money(800, 'EUR'));
    expect(terms.cancelRule?.freeMin, 2);
    expect(terms.cancelAfterArrivedIsNoShow, isTrue);
    expect(terms.maxPickupMoveMeters, 200);
  });

  test('terms whose money is in another currency are refused', () {
    final mixed = parisTerms()
      ..['noShowFee'] = {'amountMinor': 6500, 'currency': 'SEK'};
    expect(TripTerms.fromWire(mixed), isNull);
    expect(TripTerms.fromWire(null), isNull);
    expect(TripTerms.fromWire({'currency': 'EUR'}), isNull);
  });

  test('the Terms lines say the server numbers, in euro for Paris', () {
    L10n.use('fr');
    final lines = TripTermsLines.fromTerms(
      TripTerms.fromWire(parisTerms())!,
    ).lines;
    expect(lines, [
      'Attente gratuite 3 min, puis 1,10 € par minute',
      'Si vous n’êtes pas là 3 min après l’arrivée du chauffeur, des frais de 8,00 € s’appliquent',
      'Annuler après l’arrivée du chauffeur compte comme un client absent',
      'Vous pouvez déplacer le point de départ de 200 m au plus après la réservation',
    ]);
  });

  test('switch off: no "cancel after arrival" line; Swedish kronor', () {
    L10n.use('sv');
    final terms = TripTerms.fromWire(
      parisTerms()
        ..['currency'] = 'SEK'
        ..['waitPerMin'] = {'amountMinor': 1226, 'currency': 'SEK'}
        ..['noShowFee'] = {'amountMinor': 6500, 'currency': 'SEK'}
        ..['freeWaitMin'] = 5
        ..['noShowAfterMin'] = 5
        ..['cancelAfterArrivedIsNoShow'] = false
        ..['maxPickupMoveMeters'] = 350,
    )!;
    final lines = TripTermsLines.fromTerms(terms).lines;
    expect(lines, [
      'Fri väntetid 5 min, därefter 12,26 kr per minut',
      'Om du inte kommer inom 5 min efter att föraren anlänt tas en avgift på 65 kr ut',
      'Du kan flytta upphämtningen högst 350 m efter bokningen',
    ]);
  });

  test('before a trip: the served config (waiting + booking) in English', () {
    L10n.use('en');
    final config = RiderAppConfig.fromJson({
      'version': 7,
      'zoneId': 'FR-PC',
      'currency': 'EUR',
      'cancelFees': {'live': {}, 'reservation': {}},
      'booking': {'maxPickupMoveMeters': 200},
      'waiting': {
        'freeWaitMin': 3,
        'perMin': {'amountMinor': 110, 'currency': 'EUR'},
        'noShowAfterMin': 3,
        'noShowFee': {'amountMinor': 800, 'currency': 'EUR'},
        'cancelAfterArrivedIsNoShow': true,
      },
    })!;
    expect(config.cancelAfterArrivedIsNoShow, isTrue);
    expect(config.maxPickupMoveMeters, 200);
    final lines = TripTermsLines.fromConfig(config)!.lines;
    expect(lines.first, 'Free waiting 3 min, then 1,10 € per minute');
    expect(
      lines,
      contains('Cancelling after the driver has arrived counts as a no-show'),
    );
    expect(lines.last, 'You can move the pickup at most 200 m after booking');
  });

  test(
    'the pickup move default is 200 m (was 500) when the document says nothing',
    () {
      final config = RiderAppConfig.fromJson({
        'version': 1,
        'zoneId': 'Z001',
        'currency': 'SEK',
        'cancelFees': {'live': {}, 'reservation': {}},
      })!;
      expect(config.maxPickupMoveMeters, 200);
      expect(RiderAppConfig.defaultMaxPickupMoveAfterAcceptMeters, 200);
      expect(TripTerms.defaultMaxPickupMoveMeters, 200);
    },
  );

  test('cancellation fee and kind are read from the projection', () {
    final noShow = RiderCancelOutcomeFee.fromProjection({
      'cancellation': {
        'actor': 'rider',
        'fee': {'amountMinor': 6500, 'currency': 'SEK'},
        'feeKind': 'no_show',
      },
    })!;
    expect(noShow.fee, const Money(6500, 'SEK'));
    expect(noShow.kind, CancelFeeKind.noShow);
    final cancel = RiderCancelOutcomeFee.fromProjection({
      'cancellation': {
        'fee': {'amountMinor': 3500, 'currency': 'SEK'},
        'feeKind': 'cancel',
      },
    })!;
    expect(cancel.kind, CancelFeeKind.cancel);
    final free = RiderCancelOutcomeFee.fromProjection({
      'cancellation': {'fee': null},
    })!;
    expect(free.charged, isFalse);
    expect(free.kind, isNull);
    expect(RiderCancelOutcomeFee.fromProjection({}), isNull);
  });
}
