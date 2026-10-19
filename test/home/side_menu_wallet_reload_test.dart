import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/home/presentation/side_menu.dart';
import 'package:movera_rider/features/wallet/presentation/wallet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// R-UI UI-12: coming back from Wallet to the menu threw "setState()
/// callback argument returned a Future" (`setState(() => _balance =
/// _load())`). UI-10: the balance reads "0 kr", like every other price.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('back from Wallet reloads the balance without an assertion', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) => MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => RiderMenuPage.open(context),
                  child: const Text('Home body'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Home body'));
    await tester.pumpAndSettle();

    final wallet = find.bySemanticsLabel(RegExp(r'^Wallet'));
    expect(wallet, findsWidgets);
    expect(find.bySemanticsLabel('Wallet, 0 kr'), findsOneWidget);
    await tester.tap(wallet.first);
    await tester.pumpAndSettle();
    expect(find.byType(WalletAndPaymentsScreen), findsOneWidget);

    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(RiderMenuPage), findsOneWidget);
  });
}
