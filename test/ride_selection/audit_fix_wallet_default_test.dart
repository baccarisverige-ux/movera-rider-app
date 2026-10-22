import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/feature_flags/feature_flags.dart';
import 'package:movera_rider/features/payments/data/default_payment_store.dart';
import 'package:movera_rider/features/ride_booking/data/catalog_quote_repository.dart';
import 'package:movera_rider/features/ride_selection/application/ride_catalog_controller.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/ride_selection/data/ride_catalog_cache.dart';
import 'package:movera_rider/features/ride_selection/data/ride_selection_repository.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  RideSelectionController controller({DefaultPaymentStore? store}) =>
      RideSelectionController(
        store: RideSelectionRepository(),
        quotes: CatalogQuoteRepository(),
        flags: FeatureFlags(),
        paymentStore: store,
      );

  group('rider-75: a saved wallet default', () {
    test('is chosen once the balance arrives after the restore', () async {
      final store = MemoryDefaultPaymentStore('wallet');
      final selection = controller(store: store);

      // Select Ride restores the default before the balance has loaded.
      await selection.restoreDefaultPayment();
      selection.setWalletBalance(500);

      expect(selection.selectedPaymentItem()?.brand, 'wallet');
      expect(store.value, 'wallet');
    });

    test('does not override a method the rider picked meanwhile', () async {
      final selection = controller(store: MemoryDefaultPaymentStore('wallet'));
      await selection.restoreDefaultPayment();
      selection.selectPayment(
        selection.payments().indexWhere((item) => item.brand == 'cards'),
      );
      selection.setWalletBalance(500);

      expect(selection.selectedPaymentItem()?.brand, 'cards');
    });

    testWidgets('Select Ride opens on the saved wallet default', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'movera_wallet_balance': 500.0,
        PrefsDefaultPaymentStore.key: 'wallet',
      });
      final selection = RideSelectionController(
        catalog: RideCatalogController(
          api: ApiClient(
            client: MockClient(
              (_) async => http.Response(jsonEncode({'code': 'X'}), 500),
            ),
          ),
          cache: MemoryRideCatalogCache(),
        ),
        quotes: CatalogQuoteRepository(),
        flags: FeatureFlags(),
        paymentStore: const PrefsDefaultPaymentStore(),
      );
      addTearDown(selection.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: SelectRide(
            pickupAddress: 'Klockarvägen 37',
            destinationAddress: 'Arlanda Airport',
            pickupPosition: const LatLng(59.3293, 18.0686),
            destinationPosition: const LatLng(59.6519, 17.9186),
            selection: selection,
          ),
        ),
      );
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(selection.walletBalance, 500);
      expect(selection.selectedPaymentItem()?.brand, 'wallet');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 10));
    });
  });
}
