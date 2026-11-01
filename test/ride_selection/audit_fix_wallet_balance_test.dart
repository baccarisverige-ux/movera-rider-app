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
import 'package:movera_rider/features/payments/presentation/pay_with_page.dart';
import 'package:movera_rider/features/pickup/presentation/set_pickup_page.dart';
import 'package:movera_rider/features/ride_booking/data/catalog_quote_repository.dart';
import 'package:movera_rider/features/ride_selection/application/ride_catalog_controller.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/ride_selection/data/ride_catalog_cache.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// rider-74: a wallet balance below the fare cannot pay the whole ride.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  RideSelectionController selection({DefaultPaymentStore? store}) =>
      RideSelectionController(
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
        paymentStore: store,
      );

  Future<void> open(WidgetTester tester, RideSelectionController s) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(s.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: SelectRide(
          pickupAddress: 'Klockarvägen 37',
          destinationAddress: 'Arlanda Airport',
          pickupPosition: const LatLng(59.3293, 18.0686),
          destinationPosition: const LatLng(59.6519, 17.9186),
          selection: s,
        ),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  }

  testWidgets('Pay with does not take the wallet for a fare above it', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'movera_wallet_balance': 50.0,
    });
    final s = selection();
    await open(tester, s);
    expect(s.walletBalance, 50);
    expect(s.selectedPaymentItem()?.brand, 'cash');

    await tester.tap(find.text('Pay in car').first);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(PayWithPage), findsOneWidget);
    expect(find.text('Balance too low for this ride'), findsOneWidget);
    await tester.tap(find.text('Balance: 50 kr'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(s.selectedPaymentItem()?.brand, 'cash');
    await close(tester);
  });

  testWidgets('rider-r4-33: a balance just short of the fare is shown to '
      'the öre next to "too low"', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: PayWithPage(
          methods: const [
            PayWithMethod(brand: 'wallet', name: 'Wallet', detail: 'Wallet'),
            PayWithMethod(brand: 'cash', name: 'Cash', detail: 'Cash'),
          ],
          selectedBrand: 'cash',
          walletBalance: 249.6,
          walletCoversFare: false,
          promotion: null,
          brandMark: (_) => const SizedBox(width: 42, height: 38),
        ),
      ),
    );
    expect(find.text('Balance: 249,60 kr'), findsOneWidget);
    expect(find.text('Balance too low for this ride'), findsOneWidget);
  });

  testWidgets('a saved wallet default below the fare does not book', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'movera_wallet_balance': 50.0,
      PrefsDefaultPaymentStore.key: 'wallet',
    });
    final s = selection(store: const PrefsDefaultPaymentStore());
    await open(tester, s);
    expect(s.selectedPaymentItem()?.brand, 'wallet');

    await tester.tap(find.text('Select Movera'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(SetPickupPage), findsNothing);
    expect(
      find.text(
        'Your wallet balance does not cover this ride. '
        'Choose another way to pay.',
      ),
      findsOneWidget,
    );
    await close(tester);
  });

  testWidgets('a wallet that covers the fare still pays the ride', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'movera_wallet_balance': 500.0,
      PrefsDefaultPaymentStore.key: 'wallet',
    });
    final s = selection(store: const PrefsDefaultPaymentStore());
    await open(tester, s);
    expect(s.selectedPaymentItem()?.brand, 'wallet');

    await tester.tap(find.text('Select Movera'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(SetPickupPage), findsOneWidget);
    await close(tester);
  });
}
