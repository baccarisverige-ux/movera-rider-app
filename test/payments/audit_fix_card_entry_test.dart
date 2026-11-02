import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/features/payments/application/card_entry_policy.dart';
import 'package:movera_rider/features/payments/application/saved_cards_controller.dart';
import 'package:movera_rider/features/payments/data/saved_cards_store.dart';
import 'package:movera_rider/features/payments/presentation/pay_with_page.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/wallet/presentation/wallet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// FLOW-14: no payment partner holds cards yet, so staging/production must
/// not offer the local Add card form anywhere.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => CardEntryPolicy.debugOverride = null);

  AppEnv env(AppFlavor flavor) =>
      AppEnv(flavor: flavor, apiBaseUrl: 'https://api.movera.example');

  test('Add card is allowed only where mock transport is', () {
    expect(CardEntryPolicy.allowedFor(env(AppFlavor.demo)), isTrue);
    expect(CardEntryPolicy.allowedFor(env(AppFlavor.dev)), isTrue);
    expect(CardEntryPolicy.allowedFor(env(AppFlavor.test)), isTrue);
    expect(CardEntryPolicy.allowedFor(env(AppFlavor.staging)), isFalse);
    expect(CardEntryPolicy.allowedFor(env(AppFlavor.production)), isFalse);
  });

  Future<void> pumpPhone(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: home));
    await tester.pumpAndSettle();
  }

  testWidgets('wallet hides Add card when the policy is off', (tester) async {
    CardEntryPolicy.debugOverride = false;
    await pumpPhone(tester, const WalletScreen());
    expect(find.text('Pay in car'), findsOneWidget);
    expect(find.text('Add card'), findsNothing);
  });

  testWidgets('Pay with hides Add payment method when the policy is off', (
    tester,
  ) async {
    CardEntryPolicy.debugOverride = false;
    await pumpPhone(
      tester,
      PayWithPage(
        methods: const [
          PayWithMethod(brand: 'cash', name: 'Cash', detail: 'Cash'),
        ],
        selectedBrand: 'cash',
        walletBalance: 0,
        promotion: null,
        brandMark: (_) => const SizedBox(width: 42, height: 38),
      ),
    );
    expect(find.byKey(const ValueKey('pay-with-add')), findsNothing);
    CardEntryPolicy.debugOverride = true;
    await tester.pumpWidget(const SizedBox());
    await pumpPhone(
      tester,
      PayWithPage(
        methods: const [
          PayWithMethod(brand: 'cash', name: 'Cash', detail: 'Cash'),
        ],
        selectedBrand: 'cash',
        walletBalance: 0,
        promotion: null,
        brandMark: (_) => const SizedBox(width: 42, height: 38),
      ),
    );
    expect(find.byKey(const ValueKey('pay-with-add')), findsOneWidget);
  });

  test('ride selection drops the generic Card row without Add card', () {
    final cards = SavedCardsController(store: MemorySavedCardsStore());
    CardEntryPolicy.debugOverride = false;
    final off = RideSelectionController(savedCards: cards);
    expect(off.payments().map((p) => p.brand), isNot(contains('cards')));
    CardEntryPolicy.debugOverride = true;
    final on = RideSelectionController(savedCards: cards);
    expect(on.payments().map((p) => p.brand), contains('cards'));
  });
}
