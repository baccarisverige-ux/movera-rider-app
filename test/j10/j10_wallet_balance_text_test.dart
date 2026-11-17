import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/features/wallet/presentation/wallet_balance_text.dart';

String _owe(String amount) => 'You owe $amount';

void main() {
  test('TND debt of one millime reads "You owe 0.001 DT"', () {
    expect(
      walletBalanceText(const Money(-1, 'TND'), youOwe: _owe),
      'You owe 0.001 DT',
    );
  });

  test('SEK debt is exact in öre', () {
    expect(
      walletBalanceText(const Money(-1050, 'SEK'), youOwe: _owe),
      'You owe 10,50 kr',
    );
  });

  test('double noise below half a minor unit is no debt', () {
    // -0.0004 kr from a double: rounds to 0 öre, so not "You owe 0,00 kr".
    final m = walletBalanceMoney(-0.0004, 'SEK');
    expect(walletBalanceText(m, youOwe: _owe), '0,00 kr');
    expect(
      walletBalanceText(walletBalanceMoney(-0.0004, 'TND'), youOwe: _owe),
      '0.000 DT',
    );
  });

  test('positive balance has no "You owe"', () {
    expect(
      walletBalanceText(const Money(5000, 'TND'), youOwe: _owe),
      '5.000 DT',
    );
  });
}
