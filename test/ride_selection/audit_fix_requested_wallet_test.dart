import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/feature_flags/feature_flags.dart';
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

  RideSelectionController controller() => RideSelectionController(
    store: RideSelectionRepository(),
    quotes: CatalogQuoteRepository(),
    flags: FeatureFlags(),
  );

  group('rider-u186: a requested Movera Wallet method', () {
    test('is chosen once the balance arrives', () {
      final selection = controller();
      selection.selectPaymentNamed('Movera Wallet');
      expect(selection.selectedPaymentItem()?.brand, 'cash');

      selection.setWalletBalance(250);

      expect(selection.selectedPaymentItem()?.brand, 'wallet');
    });

    testWidgets('Select Ride for an edit or return ride keeps the wallet', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'movera_wallet_balance': 250.0,
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
            initialPaymentMethod: 'Movera Wallet',
          ),
        ),
      );
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(selection.walletBalance, 250);
      expect(selection.selectedPaymentItem()?.brand, 'wallet');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 10));
    });
  });
}
