import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/shared/formatters/money.dart';

/// The wallet balance as the server's integer minor units (öre, millimes):
/// a double balance is converted once, here, with the currency's exponent
/// (SEK 2 dp, TND 3 dp), so the sign and the amount come from the same
/// integer (J10 tidy, post-merge money review).
Money walletBalanceMoney(double balance, String currency) =>
    Money.fromLegacyMajor(balance, currency);

/// "You owe X" below 0 minor units (contract v0.18.84
/// debtModel.riderWallet), else the balance. A debt that rounds to 0 minor
/// units is no debt.
String walletBalanceText(
  Money balance, {
  required String Function(String amount) youOwe,
}) {
  if (balance.amountMinor < 0) {
    return youOwe(formatMoney(Money(-balance.amountMinor, balance.currency)));
  }
  return formatMoney(balance);
}
