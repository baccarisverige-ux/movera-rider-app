import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/contracts/repository_authority.dart';
import 'package:movera_rider/features/wallet/domain/wallet_balance_repository.dart';

/// The rider's wallet on the server, one balance per currency (contract
/// v0.18.28 §47, `contract.json#walletCurrency`; Movera fix job 6, owner Q4
/// 2026-11-04: "balances per currency from now on").
///
/// `GET /api/v1/wallet?currency=EUR` →
/// `Wallet {ownerId, balance: Money, balances: [Money], updatedAt}`. The
/// server owns every movement (a refund to the wallet, the part of a fare the
/// wallet pays): the movement methods never change money on the device, they
/// read the server's balance again and return it (the interface's
/// "a server implementation ignores the `previous` balance").
///
/// A balance only ever pays trips in its own currency; nothing is converted
/// or added across currencies.
class ApiWalletRepository
    implements WalletBalanceRepository, ServerBackedRepository {
  ApiWalletRepository({
    required ApiClient api,
    this.currency = Money.defaultCurrency,
  }) : _api = api;

  static const path = '/api/v1/wallet';

  final ApiClient _api;

  @override
  final String currency;

  @override
  bool get available => true;

  @override
  WalletBalanceRepository inCurrency(String currency) =>
      currency == this.currency
      ? this
      : ApiWalletRepository(api: _api, currency: currency);

  Future<Map<String, dynamic>> _read() =>
      _api.get('$path?currency=${Uri.encodeQueryComponent(currency)}');

  /// The balance in [currency] as the server holds it, in minor units.
  Future<Money> loadMoney() async {
    final json = await _read();
    final balance = Money.fromWire(json['balance']);
    if (balance != null && balance.currency == currency) return balance;
    for (final money in balancesOf(json)) {
      if (money.currency == currency) return money;
    }
    return Money(0, currency);
  }

  /// Every non-zero balance the rider holds, one per currency (never summed).
  Future<List<Money>> loadBalances() async => balancesOf(await _read());

  /// `Wallet.balances` (v0.18.28); an older server sends only `balance`.
  static List<Money> balancesOf(Map<String, dynamic> json) {
    final raw = json['balances'];
    if (raw is List) {
      return [
        for (final item in raw)
          if (Money.fromWire(item) case final Money money
              when money.amountMinor != 0)
            money,
      ];
    }
    final one = Money.fromWire(json['balance']);
    return one == null || one.amountMinor == 0 ? const [] : [one];
  }

  @override
  Future<double> loadBalance() async {
    final money = await loadMoney();
    return money.amountMinor / Money.minorPerMajor(money.currency);
  }

  @override
  Future<double> creditTopUp({
    required String paymentIntentId,
    required double previous,
    required double amount,
  }) => loadBalance();

  @override
  Future<double> debitRide({
    String? rideId,
    required double previous,
    required double amount,
  }) => loadBalance();

  @override
  Future<double> refund({required double previous, required double amount}) =>
      loadBalance();
}
