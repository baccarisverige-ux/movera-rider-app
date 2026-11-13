import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/config/rider_app_config.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/contracts/trip_terms.dart';
import 'package:movera_rider/features/active_ride/presentation/trip_terms_note.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// A1 (contract v0.18.85 `waitingPriceShown`; owner 2026-11-02 "Show price
/// incl. fee (Recommended)", Rules decisions/driver-g6.md:96): the rider
/// sees the waiting and stop-wait prices WITH the app fee, the price he
/// pays (12,26 kr -> 13,49 kr, 5 kr -> 5,50 kr, 0,50 € -> 0,55 €,
/// 0.250 DT -> 0.275 DT). The server sends them; the app never adds the fee
/// itself, and an older server's raw price is still shown.
void main() {
  Map<String, Object?> terms(
    String currency,
    int wait,
    int waitShown,
    int stop,
    int stopShown,
  ) => {
    'currency': currency,
    'freeWaitMin': 5,
    'waitPerMin': {'amountMinor': wait, 'currency': currency},
    'waitPerMinShown': {'amountMinor': waitShown, 'currency': currency},
    'noShowAfterMin': 5,
    'noShowFee': {'amountMinor': 0, 'currency': currency},
    'cancelAfterArrivedIsNoShow': false,
    'maxPickupMoveMeters': 200,
    'stopFreeWaitMin': 0,
    'stopWaitPerMin': {'amountMinor': stop, 'currency': currency},
    'stopWaitPerMinShown': {'amountMinor': stopShown, 'currency': currency},
  };

  tearDown(() => L10n.use('en'));

  test('SEK: the Terms say 13,49 kr and 5,50 kr a minute (incl. fee)', () {
    L10n.use('sv');
    final lines = TripTermsLines.fromTerms(
      TripTerms.fromWire(terms('SEK', 1226, 1349, 500, 550))!,
    ).lines;
    expect(lines.first, 'Fri väntetid 5 min, därefter 13,49 kr per minut');
    expect(lines.last, 'Väntan vid stopp: 5,50 kr/min');
  });

  test('EUR: the owner\'s 0,55 € a minute', () {
    L10n.use('fr');
    final lines = TripTermsLines.fromTerms(
      TripTerms.fromWire(terms('EUR', 50, 55, 50, 55))!,
    ).lines;
    expect(lines.first, 'Attente gratuite 5 min, puis 0,55 € par minute');
    expect(lines.last, 'Attente à un arrêt : 0,55 €/min');
  });

  test('TND: 0.275 DT a minute (three decimals)', () {
    L10n.use('en');
    final lines = TripTermsLines.fromTerms(
      TripTerms.fromWire(terms('TND', 250, 275, 250, 275))!,
    ).lines;
    expect(lines.first, contains('0.275'));
    expect(lines.first, isNot(contains('0.250')));
    expect(lines.last, contains('0.275'));
  });

  test('an older server (no shown field): the raw price, as before', () {
    final raw = terms('SEK', 1226, 0, 500, 0)
      ..remove('waitPerMinShown')
      ..remove('stopWaitPerMinShown');
    L10n.use('sv');
    final lines = TripTermsLines.fromTerms(TripTerms.fromWire(raw)!).lines;
    expect(lines.first, 'Fri väntetid 5 min, därefter 12,26 kr per minut');
  });

  test('a shown price in another currency is ignored (raw one kept)', () {
    final mixed = terms('SEK', 1226, 1349, 500, 550)
      ..['waitPerMinShown'] = {'amountMinor': 1349, 'currency': 'EUR'};
    final parsed = TripTerms.fromWire(mixed)!;
    expect(parsed.waitPerMin, const Money(1226, 'SEK'));
    L10n.use('sv');
    expect(
      TripTermsLines.fromTerms(parsed).lines.first,
      'Fri väntetid 5 min, därefter 12,26 kr per minut',
    );
  });

  test('before a trip: the served config perMinShown, per category', () {
    L10n.use('sv');
    final config = RiderAppConfig.fromJson({
      'version': 3,
      'zoneId': 'Z001',
      'currency': 'SEK',
      'waiting': {
        'freeWaitMin': 5,
        'perMin': {'amountMinor': 1226, 'currency': 'SEK'},
        'perMinShown': {'amountMinor': 1349, 'currency': 'SEK'},
        'noShowAfterMin': 5,
        'noShowFee': {'amountMinor': 6500, 'currency': 'SEK'},
        'byCategory': {
          'premium': {
            'freeWaitMin': 5,
            'perMin': {'amountMinor': 1690, 'currency': 'SEK'},
            'perMinShown': {'amountMinor': 1893, 'currency': 'SEK'},
            'noShowAfterMin': 5,
            'noShowFee': {'amountMinor': 6500, 'currency': 'SEK'},
          },
        },
      },
    })!;
    expect(
      TripTermsLines.fromConfig(config)!.lines.first,
      'Fri väntetid 5 min, därefter 13,49 kr per minut',
    );
    expect(
      TripTermsLines.fromConfig(config, categoryId: 'premium')!.lines.first,
      'Fri väntetid 5 min, därefter 18,93 kr per minut',
    );
  });
}
