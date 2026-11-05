import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/wallet/presentation/wallet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tree_snapshot.dart';

// Base split (owner 2026-11-04 "Split it first", rule 25): wallet.dart is
// split with no behaviour change. Both snapshots were written before the
// split and must match after it.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  for (final tab in [0, 1]) {
    testWidgets('wallet & payments, tab $tab', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(home: WalletAndPaymentsScreen(initialTab: tab)),
      );
      await tester.pumpAndSettle();
      expectTreeSnapshot(
        tester,
        tab == 0 ? 'rider_wallet_tab_wallet' : 'rider_wallet_tab_payments',
      );
    });
  }
}
