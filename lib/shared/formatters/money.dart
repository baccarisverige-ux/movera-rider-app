import 'package:movera_rider/core/contracts/money.dart';

/// Öre (minor units) as kronor to the öre: "102,00 kr", "102,50 kr". Same
/// format as [formatMoney], so one ride never reads "kr 659" on one screen
/// and "659 kr" on the next (R-UI UI-10).
String formatSek(int minor) => formatMoney(Money(minor));

/// A kronor amount (major units, not öre) as "X kr", exact to the öre
/// ("100,40 kr"). Use [formatSek] instead when the value is in minor units.
String formatKr(num amount) => formatMoney(Money.fromLegacyMajor(amount));

/// The app's one money format, per currency (Q7: the pickup's zone decides
/// the currency):
///
/// * SEK: "35,50 kr", "35,00 kr", "1 250,00 kr": always the öre, with a
///   comma, a space between thousands.
/// * EUR: "7,41 €", "35,00 €", "1 250,00 €": always with cents.
/// * TND: "7.410 DT", "5.000 DT", "1 250.000 DT": a dot, always the three
///   millime digits, a space between thousands (contract v0.18.59 §81).
/// * Any other code: "12.50 XYZ".
///
/// Price format (owner 2026-11-14: "make sure rider and driver app show
/// correct prices every where", "Check all apps"): every amount uses its
/// currency's decimals, whole amounts keep them, and nothing is rounded to
/// whole kronor any more. [whole] no longer rounds: it is kept, and
/// ignored, only so callers in files other open jobs are changing (J10)
/// still build; drop it from them once those jobs merge.
String formatMoney(Money money, {bool whole = false}) {
  switch (money.currency) {
    case 'SEK':
      // rider-r4-16: öre with a comma, like euros and dinars ("35,50 kr").
      return '${_grouped(money.majorString).replaceFirst('.', ',')} kr';
    case 'EUR':
      return '${_grouped(money.majorString).replaceFirst('.', ',')} €';
    case 'TND':
      return '${_grouped(money.majorString)} DT';
    default:
      return '${money.majorString} ${money.currency}';
  }
}

/// [formatMoney] for amounts the server works out (BQ-M22 cancel sheet):
/// the decimals of a whole amount are kept ("40,00 kr", "5.000 DT",
/// "8,00 €") and thousands are grouped ("1 000,00 kr"), as [formatMoney]
/// does since the price format job (PF #615); every space is a non-breaking
/// one, so an amount never breaks over two lines ("40,00 / kr.",
/// supervisor S5).
String formatMoneyFull(Money money) =>
    formatMoney(money).replaceAll(' ', '\u00A0');

/// "1250.000" → "1 250.000": a space between thousands (contract v0.18.59
/// §81 for the dinar; kronor and euros the same, as the admin and the
/// server write them: "1 250,00 kr").
String _grouped(String major) {
  final negative = major.startsWith('-');
  final parts = (negative ? major.substring(1) : major).split('.');
  final grouped = parts.first.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ' ',
  );
  final frac = parts.length > 1 ? '.${parts[1]}' : '';
  return '${negative ? '-' : ''}$grouped$frac';
}

/// [money] on a chip the rider picks from a row (the tip chips, the raise
/// steps) and on the unpaid-fee line: exactly [formatMoney], decimals kept
/// ("20,00 kr", "5,00 €", "2.000 DT"). Contract v0.18.89
/// `moneyDisplay.wholeAmounts`: no short form on any screen, list or card
/// (owner 2026-11-14; supervisor M2, Rules audits/impact/pd2-pf-supervisor.md).
String formatMoneyShort(Money money) => formatMoney(money);

/// The symbol of [currency]: "kr", "€", "DT", else the code itself.
String currencySymbol(String currency) => switch (currency) {
  'SEK' => 'kr',
  'EUR' => '€',
  'TND' => 'DT',
  _ => currency,
};

/// A major-unit amount in [currency], exact ("50,00 kr", "5,00 €",
/// "12.350 DT"; price format, owner 2026-11-14).
String formatMajor(num major, String currency) =>
    formatMoney(Money.fromLegacyMajor(major, currency));
