import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/features/profile/domain/rider_outstanding.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/quote.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Owner 2026-11-07 (item 12): with an unpaid fee from an earlier trip,
/// Choose ride showed the list price first (259 kr) and jumped to the
/// server's quote (408 kr = 259 + 149 unpaid) when it landed. The server
/// adds the fee from the first quote (movera-server quotes/service.ts
/// owedHere -> fareLines.outstanding_fee); the app now shows it from the
/// first price, with one short line.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RiderOutstanding.reset();
  });
  tearDown(RiderOutstanding.reset);

  RideQuote quote() => RideQuote(
    id: 'q1',
    rideType: 'economy',
    totalMinor: 40800,
    currency: 'SEK',
    expiresAt: DateTime.now().add(const Duration(minutes: 5)),
    outstandingFeeMinor: 14900,
    serverHeld: true,
  );

  test(
    'the list price already carries the unpaid fee: no jump at the quote',
    () {
      RiderOutstanding.current.value = const RiderOutstanding(
        byCurrency: [Money(14900, 'SEK')],
      );
      final selection = RideSelectionController(currency: 'SEK');
      addTearDown(selection.dispose);
      final before = selection.priceFor('economy', 259);
      selection.adoptQuote('economy', quote());
      final after = selection.priceFor('economy', 259);
      expect(before, 408, reason: 'first price $before, quote $after');
      expect(after, 408);
      expect(selection.unpaidFeeFor('economy'), const Money(14900, 'SEK'));
    },
  );

  test('a debt in another currency is not added', () {
    RiderOutstanding.current.value = const RiderOutstanding(
      byCurrency: [Money(1000, 'EUR')],
    );
    final selection = RideSelectionController(currency: 'SEK');
    addTearDown(selection.dispose);
    expect(selection.priceFor('economy', 259), 259);
    expect(selection.unpaidFeeFor('economy'), isNull);
  });

  test('the short line reads « +149 kr frais impayés » (sv/en the same)', () {
    expect(
      lookupAppLocalizations(const Locale('fr')).priceUnpaidFeeShort('149 kr'),
      '+149 kr frais impayés',
    );
    expect(
      lookupAppLocalizations(const Locale('sv')).priceUnpaidFeeShort('149 kr'),
      '+149 kr obetald avgift',
    );
    expect(
      lookupAppLocalizations(const Locale('en')).priceUnpaidFeeShort('149 kr'),
      '+149 kr unpaid fee',
    );
  });
}
