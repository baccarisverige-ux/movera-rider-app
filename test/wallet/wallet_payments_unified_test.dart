import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/wallet/presentation/wallet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('one destination moves between wallet and payment preferences', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: WalletAndPaymentsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Wallet & Payments'), findsOneWidget);
    expect(find.text('Available balance'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Payments'));
    await tester.pumpAndSettle();
    expect(find.text('How would you like\nto pay?'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Wallet'));
    await tester.pumpAndSettle();
    expect(find.text('Available balance'), findsOneWidget);
  });

  testWidgets('payment controls fit a small screen at 200 percent text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2)),
          child: WalletAndPaymentsScreen(initialTab: 1),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final addMethod = find.text('Add card');
    await tester.ensureVisible(addMethod);
    await tester.tap(addMethod);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
