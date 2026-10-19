import 'package:movera_rider/core/contracts/money.dart';

/// Öre (minor units) as whole kronor: "102 kr". Same format as
/// [formatMoney], so one ride never reads "kr 659" on one screen and
/// "659 kr" on the next (R-UI UI-10).
String formatSek(int minor) => formatMoney(Money((minor / 100).round() * 100));

/// A whole-kronor amount (not minor units/öre) as "X kr", rounded to the
/// krona. Use [formatSek] instead when the value is in minor units.
String formatKr(num amount) => formatMoney(Money(amount.round() * 100));

/// Contract Money for display: "35 kr", "35.50 kr", "12.500 DT" (ISO
/// exponent; whole amounts drop the decimals).
String formatMoney(Money money) {
  const symbols = {'SEK': 'kr', 'EUR': '€', 'TND': 'DT'};
  final symbol = symbols[money.currency] ?? money.currency;
  final exponent = Money.exponentOf(money.currency);
  final major = money.majorString;
  final whole = exponent == 0 || money.amountMinor % _pow10(exponent) == 0;
  return '${whole ? major.split('.').first : major} $symbol';
}

int _pow10(int exponent) {
  var value = 1;
  for (var i = 0; i < exponent; i++) {
    value *= 10;
  }
  return value;
}
