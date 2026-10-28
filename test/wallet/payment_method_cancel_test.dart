import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/payments/presentation/add_card_page.dart';
import 'package:movera_rider/features/wallet/application/wallet_controller.dart';
import 'package:movera_rider/features/wallet/presentation/wallet.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'Add card opens the demo card form and saves nothing when closed',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MaterialApp(home: WalletScreen()));
      await tester.pumpAndSettle();

      // PayPal, Klarna and Swish as its own method are gone (owner request).
      expect(find.text('PayPal'), findsNothing);
      expect(find.text('Klarna'), findsNothing);
      expect(find.text('Swish'), findsNothing);
      expect(find.text('Cash'), findsOneWidget);

      final addPayment = find.text('Add card');
      await tester.ensureVisible(addPayment);
      await tester.tap(addPayment);
      await tester.pumpAndSettle();

      expect(find.byType(AddCardPage), findsOneWidget);
      expect(find.text(L10n.current.addCardDemoNote), findsOneWidget);
      // Demo form: number, expiry, CVC and name; Save is off until valid.
      expect(find.byType(TextField), findsNWidgets(4));
      final save = tester.widget<FilledButton>(
        find.byKey(const ValueKey('add-card-save')),
      );
      expect(save.onPressed, isNull);

      await tester.pageBack();
      await tester.pumpAndSettle();
      final saved = await WalletController().loadPayments();
      expect(saved.defaultMethod, 'cash');
      expect(saved.extraMethods, isEmpty);
    },
  );
}
