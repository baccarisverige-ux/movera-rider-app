import 'package:movera_rider/core/contracts/money.dart';

/// Öre (minor units) as whole kronor: "102 kr". Same format as
/// [formatMoney], so one ride never reads "kr 659" on one screen and
/// "659 kr" on the next (R-UI UI-10).
String formatSek(int minor) => formatMoney(Money(minor), whole: true);

/// A whole-kronor amount (not minor units/öre) as "X kr", rounded to the
/// krona. Use [formatSek] instead when the value is in minor units.
String formatKr(num amount) =>
    formatMoney(Money.fromLegacyMajor(amount), whole: true);

/// The app's one money format, per currency (Q7: the pickup's zone decides
/// the currency):
///
/// * SEK: "35 kr", "35.50 kr"; with [whole] rounded to the krona, "36 kr"
///   (the Swedish fare look, unchanged).
/// * EUR: "7,41 €", always with cents.
/// * TND: "7,410 DT", always with the three millime digits.
/// * Any other code: "12.50 XYZ".
///
/// [whole] only rounds SEK: euro and dinar fares are shown to the minor unit.
String formatMoney(Money money, {bool whole = false}) {
  switch (money.currency) {
    case 'SEK':
      if (whole) {
        final unit = Money.minorPerMajor('SEK');
        final kronor = (money.amountMinor / unit).round();
        return '$kronor kr';
      }
      final major = money.majorString;
      final isWhole = money.amountMinor % Money.minorPerMajor('SEK') == 0;
      return '${isWhole ? major.split('.').first : major} kr';
    case 'EUR':
      return '${money.majorString.replaceFirst('.', ',')} €';
    case 'TND':
      return '${money.majorString.replaceFirst('.', ',')} DT';
    default:
      return '${money.majorString} ${money.currency}';
  }
}

/// The symbol of [currency]: "kr", "€", "DT", else the code itself.
String currencySymbol(String currency) => switch (currency) {
  'SEK' => 'kr',
  'EUR' => '€',
  'TND' => 'DT',
  _ => currency,
};

/// A whole-unit amount in [currency] ("+50 kr", "+5,00 €").
String formatMajor(num major, String currency, {bool whole = true}) =>
    formatMoney(Money.fromLegacyMajor(major, currency), whole: whole);
