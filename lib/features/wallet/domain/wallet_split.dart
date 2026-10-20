import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/shared/formatters/money.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// "Use wallet balance first": how a fare is split between the Movera
/// Wallet and the chosen payment method, in integer öre (DECISIONS.md P1).
///
/// The rider sees whole kronor. The total and the wallet part are each
/// rounded once and the remainder shown is their difference, so the parts
/// on screen always add up to the total on screen.
class WalletSplit {
  const WalletSplit._({
    required this.totalMinor,
    required this.walletMinor,
    required this.currency,
  });

  /// No wallet part: the method pays [totalMinor].
  const WalletSplit.none(this.totalMinor, [this.currency = Money.defaultCurrency])
    : walletMinor = 0;

  /// The wallet covers up to [balanceMinor] of [totalMinor].
  factory WalletSplit.of({
    required int totalMinor,
    required int balanceMinor,
    String currency = Money.defaultCurrency,
  }) {
    if (totalMinor <= 0 || balanceMinor <= 0) {
      return WalletSplit.none(totalMinor < 0 ? 0 : totalMinor, currency);
    }
    return WalletSplit._(
      totalMinor: totalMinor,
      walletMinor: balanceMinor >= totalMinor ? totalMinor : balanceMinor,
      currency: currency,
    );
  }

  /// A split already decided (a booked ride carries its wallet part).
  factory WalletSplit.booked({
    required int totalMinor,
    required int walletMinor,
    String currency = Money.defaultCurrency,
  }) => WalletSplit.of(
    totalMinor: totalMinor,
    balanceMinor: walletMinor,
    currency: currency,
  );

  final int totalMinor;
  final int walletMinor;

  /// ISO-4217 code of every part (Q8: the wallet of the trip's currency).
  final String currency;

  int get remainderMinor => totalMinor - walletMinor;

  bool get usesWallet => walletMinor > 0;

  /// The wallet pays the whole fare.
  bool get paidByWallet => usesWallet && remainderMinor <= 0;

  int get totalKr => roundMinorToKr(totalMinor);

  int get walletKr => roundMinorToKr(walletMinor);

  /// What the chosen method pays, as shown: total shown minus wallet shown.
  int get remainderKr => totalKr - walletKr;

  bool get _kronor => currency == Money.defaultCurrency;

  /// The parts as shown. Kronor are whole (the remainder is the total
  /// shown less the wallet shown, so the parts add up); euros and dinars
  /// are exact to the minor unit, so they add up as they are.
  String get totalLabel => _kronor
      ? formatKr(totalKr)
      : formatMoney(Money(totalMinor, currency));
  String get walletLabel => _kronor
      ? formatKr(walletKr)
      : formatMoney(Money(walletMinor, currency));
  String get remainderLabel => _kronor
      ? formatKr(remainderKr)
      : formatMoney(Money(remainderMinor, currency));
}

/// The one rounding rule for showing öre as whole kronor.
int roundMinorToKr(int minor) =>
    (minor / Money.minorPerMajor(Money.defaultCurrency)).round();

/// Kronor (a stored balance) to öre.
int krToMinor(double kr) => Money.fromLegacyMajor(kr).amountMinor;

/// The payment line on the Finding and Waiting cards, showing the same
/// split the rider saw before booking: "Visa •••• 4242 · 259 kr", or with
/// the wallet "Visa •••• 4242 209 kr · Wallet 50 kr". [priceKr] is in whole
/// units of [currency]; the wallet part is in the same currency (Q8).
String bookedPaymentLine({
  required String paymentMethod,
  required double priceKr,
  int walletMinor = 0,
  String separator = ' · ',
  String currency = Money.defaultCurrency,
}) {
  final fare = Money.fromLegacyMajor(priceKr, currency);
  final split = WalletSplit.booked(
    totalMinor: fare.amountMinor,
    walletMinor: walletMinor,
    currency: currency,
  );
  if (!split.usesWallet) {
    return '$paymentMethod$separator${formatMoney(fare, whole: true)}';
  }
  if (split.paidByWallet) {
    return '${L10n.current.paidByWallet}$separator${split.totalLabel}';
  }
  return '$paymentMethod ${split.remainderLabel}$separator'
      '${L10n.current.walletAmount(split.walletLabel)}';
}
