import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/demo_features.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/features/wallet/application/wallet_controller.dart';
import 'package:movera_rider/features/wallet/data/api_wallet_repository.dart';
import 'package:movera_rider/features/wallet/presentation/wallet.dart';
import 'package:movera_rider/shared/formatters/money.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fix job 6 on the real Wallet screen (owner Q4 + "Turn it on" +
/// top-up "Later, with card payments").
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    DemoFeatures.debugOverride = false; // as a release build
  });
  tearDown(() => DemoFeatures.debugOverride = null);

  WalletController serverWallet() => WalletController(
    balances: ApiWalletRepository(
      api: ApiClient(
        env: const AppEnv(
          flavor: AppFlavor.staging,
          apiBaseUrl: 'https://x.invalid',
        ),
        client: MockClient((request) async {
          final wanted = request.url.queryParameters['currency'] ?? 'SEK';
          const balances = [
            {'amountMinor': 6500, 'currency': 'EUR'},
            {'amountMinor': 3000, 'currency': 'SEK'},
          ];
          return http.Response(
            jsonEncode({
              'ownerId': 'rdr_1',
              'balance': balances.firstWhere((b) => b['currency'] == wanted),
              'balances': balances,
              'updatedAt': '2026-11-04T10:00:00Z',
            }),
            200,
          );
        }),
      ),
    ),
  );

  testWidgets('each currency is shown on its own, never a sum; top-up says '
      'unavailable and charges nothing', (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WalletHome(wallet: serverWallet())),
      ),
    );
    await tester.pumpAndSettle();

    final line = tester
        .widget<Text>(find.byKey(const ValueKey('wallet-balances-by-currency')))
        .data!;
    expect(
      line,
      '${formatMoney(const Money(6500, 'EUR'))} · '
      '${formatMoney(const Money(3000, 'SEK'))}',
    );
    expect(find.text(formatMoney(const Money(3000, 'SEK'))), findsOneWidget);
    expect(find.text(formatMoney(const Money(9500, 'SEK'))), findsNothing);

    final addFunds = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Add funds unavailable'),
    );
    expect(addFunds.onPressed, isNull);
  });
}
