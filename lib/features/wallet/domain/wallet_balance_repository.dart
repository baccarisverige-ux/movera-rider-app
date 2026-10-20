/// The wallet balance and its movements (ARCH-6, contract C-10).
///
/// PROPOSED, needs agreement with Driver, Admin and backend: a server
/// ledger behind `GET /api/v1/wallet` → `{balanceMinor, currency, entries[]}`
/// that credits a top-up itself when the payment intent with
/// `purpose: wallet_topup` is captured, and debits a wallet-paid ride at
/// payment finalisation. A server implementation therefore ignores the
/// `previous` balance the client passes and returns the balance it holds.
///
/// Only the device-local ledger and a disabled one exist today; release
/// builds compose the disabled one (see `RepositoryComposition`).
abstract interface class WalletBalanceRepository {
  /// False when this build has no wallet: top-ups must not charge a card
  /// with nowhere authoritative to credit the money, and no ride is debited.
  bool get available;

  /// ISO-4217 code of the balance and every movement. A balance pays only
  /// trips in this currency; the app never converts (Q7).
  String get currency;

  /// Q8: the rider has one wallet balance per currency. The balance in
  /// [currency] (this one when it is already in [currency]).
  WalletBalanceRepository inCurrency(String currency);

  Future<double> loadBalance();

  /// Records a captured top-up of [amount] (whole units of [currency]) and returns the new balance.
  Future<double> creditTopUp({
    required String paymentIntentId,
    required double previous,
    required double amount,
  });

  /// Takes a completed wallet-paid ride off the balance.
  Future<double> debitRide({
    String? rideId,
    required double previous,
    required double amount,
  });

  Future<double> refund({required double previous, required double amount});
}

/// Raised when a wallet movement is asked of a build whose wallet is off.
class WalletUnavailableException implements Exception {
  const WalletUnavailableException();

  @override
  String toString() => 'WalletUnavailableException(wallet is not available)';
}
