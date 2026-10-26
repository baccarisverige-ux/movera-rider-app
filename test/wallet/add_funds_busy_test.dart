import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/wallet/application/wallet_controller.dart';
import 'package:movera_rider/features/wallet/data/wallet_repository.dart';
import 'package:movera_rider/features/wallet/presentation/wallet.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemWallet extends WalletStore {
  double balance = 0;

  @override
  Future<double> loadBalance() async => balance;

  @override
  Future<void> saveBalance(double value) async {
    balance = value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> openAndSimulate(WidgetTester tester) async {
    await tester.tap(find.text('Add funds (demo)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simulate top-up'));
  }

  testWidgets(
    'Add funds re-enables after a top-up completes, with exactly one credit',
    (tester) async {
      final store = _MemWallet();
      await tester.pumpWidget(
        MaterialApp(
          home: WalletHome(wallet: WalletController(store: store)),
        ),
      );
      await tester.pumpAndSettle();

      await openAndSimulate(tester);
      await tester.pumpAndSettle();

      expect(store.balance, 200);
      final settledButton = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Add funds (demo)'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(settledButton.onPressed, isNotNull);
    },
  );

  testWidgets('two separate top-ups each apply exactly once', (tester) async {
    final store = _MemWallet();
    await tester.pumpWidget(
      MaterialApp(
        home: WalletHome(wallet: WalletController(store: store)),
      ),
    );
    await tester.pumpAndSettle();

    await openAndSimulate(tester);
    await tester.pumpAndSettle();
    expect(store.balance, 200);

    await openAndSimulate(tester);
    await tester.pumpAndSettle();
    expect(store.balance, 400);
  });
}
