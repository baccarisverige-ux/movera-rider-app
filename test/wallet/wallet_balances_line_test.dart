import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/features/wallet/presentation/wallet_balances_line.dart';
import 'package:movera_rider/shared/formatters/money.dart';

/// Fix job 6 (owner Q4): each wallet balance in its own currency, never a sum.
void main() {
  Future<void> pump(WidgetTester tester, List<Money> balances) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: WalletBalancesLine(load: () async => balances)),
        ),
      );

  testWidgets('a EUR and a SEK balance are shown side by side', (tester) async {
    await pump(tester, const [Money(6500, 'EUR'), Money(3000, 'SEK')]);
    await tester.pumpAndSettle();
    final shown = tester
        .widget<Text>(find.byKey(const ValueKey('wallet-balances-by-currency')))
        .data!;
    expect(
      shown,
      '${formatMoney(const Money(6500, 'EUR'))} · '
      '${formatMoney(const Money(3000, 'SEK'))}',
    );
    expect(shown, isNot(contains('95')));
  });

  testWidgets('one balance or none adds no extra line', (tester) async {
    await pump(tester, const [Money(6500, 'EUR')]);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('wallet-balances-by-currency')),
      findsNothing,
    );
    await pump(tester, const []);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('wallet-balances-by-currency')),
      findsNothing,
    );
  });
}
