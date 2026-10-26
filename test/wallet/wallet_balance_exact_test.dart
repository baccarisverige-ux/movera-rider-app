import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/wallet/data/wallet_repository.dart';
import 'package:movera_rider/features/wallet/presentation/wallet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// rider-r5-14: a balance with öre is shown exactly, not rounded up to a
/// krona the wallet does not have.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('49,63 kr is not shown as 50 kr', (tester) async {
    SharedPreferences.setMockInitialValues({WalletStore.balanceKey: 49.63});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) => const MaterialApp(home: WalletHome()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('49,63 kr'), findsOneWidget);
  });
}
