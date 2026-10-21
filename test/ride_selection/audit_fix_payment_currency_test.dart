import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/feature_flags/feature_flags.dart';
import 'package:movera_rider/features/ride_booking/data/catalog_quote_repository.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/quote.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/ride_selection/data/ride_selection_repository.dart';

void main() {
  RideSelectionController controller() => RideSelectionController(
    store: RideSelectionRepository(),
    quotes: CatalogQuoteRepository(),
    flags: FeatureFlags(),
  );

  RideQuote eurQuote() => RideQuote(
    id: 'q-eur',
    rideType: 'economy',
    totalMinor: 2500,
    currency: 'EUR',
    expiresAt: DateTime.now().add(const Duration(minutes: 2)),
    signedPayload: 'mock-api',
  );

  group('rider-u184: a quote in another currency', () {
    test('keeps the chosen method when the wallet row drops out', () {
      final selection = controller();
      selection.walletCurrency = 'SEK';
      selection.setWalletBalance(50);
      expect(
        selection.payments().map((item) => item.brand),
        contains('wallet'),
      );
      selection.selectPaymentByBrand('cards');
      expect(selection.selectedPaymentItem()?.brand, 'cards');

      selection.adoptQuote('economy', eurQuote());

      expect(
        selection.payments().map((item) => item.brand),
        isNot(contains('wallet')),
      );
      expect(selection.selectedPaymentItem()?.brand, 'cards');
    });

    test('falls back to Cash when the wallet itself was chosen', () {
      final selection = controller();
      selection.walletCurrency = 'SEK';
      selection.setWalletBalance(50);
      selection.selectPaymentByBrand('wallet');
      expect(selection.selectedPaymentItem()?.brand, 'wallet');

      selection.adoptQuote('economy', eurQuote());

      expect(selection.selectedPaymentItem()?.brand, 'cash');
    });
  });
}
