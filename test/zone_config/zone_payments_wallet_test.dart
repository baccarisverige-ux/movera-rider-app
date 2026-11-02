import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/feature_flags/feature_flags.dart';
import 'package:movera_rider/core/location/location_repository.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/ride_selection/data/ride_selection_repository.dart';
import 'package:movera_rider/features/wallet/application/wallet_controller.dart';
import 'package:movera_rider/features/wallet/data/wallet_repository.dart';
import 'package:movera_rider/features/wallet/domain/wallet_split.dart';
import 'package:movera_rider/features/wallet/presentation/wallet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Owner Q7 FINAL: Cash, Card, Apple Pay and Google Pay in every country,
/// as the zone's config lists them; no Swish, Klarna or PayPal. Q8: one
/// wallet balance per currency, used first, never converted.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('payment methods (Q7)', () {
    test('the offered rows are the wallet and the four zone methods only', () {
      final names = [
        for (final item in RideSelectionRepository().payments()) item.name,
      ];
      expect(names, ['Movera Wallet', 'Apple Pay', 'Card', 'Cash']);
      for (final item in RideSelectionRepository().payments()) {
        expect(
          '${item.name} ${item.detail}'.toLowerCase(),
          isNot(matches(RegExp('swish|klarna|paypal'))),
        );
      }
    });

    test('a method the zone config leaves out is not offered', () {
      final selection = RideSelectionController(flags: const FeatureFlags());
      addTearDown(selection.dispose);
      // Tests run as Android: Card, Cash (no Google Pay since G8).
      expect(selection.payments().map((p) => p.brand), ['cards', 'cash']);

      selection.setZonePaymentMethods(const ['cash', 'card']);
      expect(selection.payments().map((p) => p.brand), ['cards', 'cash']);
      expect(selection.selectedPaymentItem()?.brand, 'cash');

      selection.setZonePaymentMethods(const ['card']);
      expect(selection.payments().map((p) => p.brand), ['cards']);
      // Cash is gone, so the choice falls back to the first offered.
      expect(selection.selectedPaymentItem()?.brand, 'cards');
    });

    test('an old booking that said Swish or Pay in car books Cash', () {
      final selection = RideSelectionController(flags: const FeatureFlags());
      addTearDown(selection.dispose);
      selection.selectPaymentByBrand('cards');
      selection.selectPaymentNamed('Swish');
      expect(selection.selectedPaymentItem()?.name, 'Cash');
      selection.selectPaymentByBrand('cards');
      selection.selectPaymentNamed('Pay in car');
      expect(selection.selectedPaymentItem()?.name, 'Cash');
    });
  });

  group('one wallet per currency (Q8)', () {
    test('each currency has its own balance; kronor keeps its key', () async {
      SharedPreferences.setMockInitialValues({
        WalletStore.balanceKey: 120.0,
        'movera_wallet_balance.EUR': 15.5,
      });
      final kronor = LocalWalletRepository();
      final euros = kronor.inCurrency('EUR');
      final dinars = kronor.inCurrency('TND');

      expect(euros.currency, 'EUR');
      expect(await kronor.loadBalance(), 120.0);
      expect(await euros.loadBalance(), 15.5);
      expect(await dinars.loadBalance(), 0);

      await dinars.creditTopUp(
        paymentIntentId: 'pi_1',
        previous: 0,
        amount: 30,
      );
      expect(await dinars.loadBalance(), 30);
      expect(await kronor.loadBalance(), 120.0, reason: 'no conversion');
      expect(await euros.loadBalance(), 15.5);
    });

    test(
      'a euro trip paid by wallet is taken off the euro balance only',
      () async {
        SharedPreferences.setMockInitialValues({
          WalletStore.balanceKey: 500.0,
          'movera_wallet_balance.EUR': 40.0,
        });
        final snapshot = RideSnapshot(
          status: RideStatus.paymentFinalized,
          savedAt: DateTime.now(),
          pickupAddress: 'Louvre',
          destinationAddress: 'Gare du Nord',
          pickupLat: 48.86,
          pickupLng: 2.34,
          destinationLat: 48.88,
          destinationLng: 2.35,
          rideType: 'Economy',
          price: 24.6,
          currency: 'EUR',
          paymentMethod: 'Movera Wallet',
          paymentMethodId: 'wallet',
          rideId: 'ride-eur-wallet',
        );
        final wallet = WalletController();

        expect(
          await wallet.chargeCompletedRide(snapshot, rideId: 'ride-eur-wallet'),
          closeTo(15.4, 1e-9),
        );
        expect(await wallet.loadBalance(), 500.0);
        expect(
          await wallet.forCurrency('EUR').loadBalance(),
          closeTo(15.4, 1e-9),
        );
        // Never twice.
        expect(
          await wallet.chargeCompletedRide(snapshot, rideId: 'ride-eur-wallet'),
          isNull,
        );
      },
    );

    test(
      'the euro balance is used first on a euro trip, exact to the cent',
      () {
        final selection = RideSelectionController(
          flags: const FeatureFlags(),
          currency: 'EUR',
        );
        addTearDown(selection.dispose);
        selection
          ..walletCurrency = 'EUR'
          ..setWalletBalance(5.5);
        final split = selection.walletSplitFor(
          const Money(2460, 'EUR').amountMinor,
        );
        expect(split.usesWallet, isTrue);
        expect(split.walletLabel, '5,50 €');
        expect(split.remainderLabel, '19,10 €');
        expect(
          bookedPaymentLine(
            paymentMethod: 'Card',
            priceKr: 24.6,
            walletMinor: 550,
            currency: 'EUR',
          ),
          'Card 19,10 € · Wallet 5,50 €',
        );
        // A balance in another currency never pays.
        selection.walletCurrency = 'SEK';
        expect(selection.walletSplitFor(2460).usesWallet, isFalse);
      },
    );

    testWidgets('the Wallet page shows the balance of each currency', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        WalletStore.balanceKey: 50.0,
        'movera_wallet_balance.EUR': 12.0,
        // The rider was last in Tunis.
        LocationRepository.lastGoodFixKey: '{"lat":36.80,"lng":10.18}',
        'movera_wallet_balance.TND': 7.5,
      });
      tester.view.physicalSize = const Size(390, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(home: WalletHome(wallet: WalletController())),
      );
      await tester.pumpAndSettle();

      expect(find.text('7,500 DT'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('wallet-currency-EUR')));
      await tester.pumpAndSettle();
      expect(find.text('12,00 €'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('wallet-currency-SEK')));
      await tester.pumpAndSettle();
      expect(find.text('50 kr'), findsOneWidget);
    });
  });
}
