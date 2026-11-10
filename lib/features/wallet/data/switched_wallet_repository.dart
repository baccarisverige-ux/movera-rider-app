import 'package:movera_rider/core/contracts/repository_authority.dart';
import 'package:movera_rider/features/wallet/domain/wallet_balance_repository.dart';

/// Owner 2026-11-10 "Yes, fix": the wallet follows the admin switch at once.
/// Both sides are built at start-up and every call asks [isOn] (the
/// server's `features.wallet`, via `FeatureFlags.wallet`), so an admin who
/// switches the wallet on mid-session needs no app restart; switched off,
/// the fail-closed stand-in answers.
class SwitchedWalletRepository
    implements WalletBalanceRepository, ServerBackedRepository {
  SwitchedWalletRepository({
    required this.on,
    required this.off,
    required this.isOn,
  });

  final WalletBalanceRepository on;
  final WalletBalanceRepository off;
  final bool Function() isOn;

  WalletBalanceRepository get _now => isOn() ? on : off;

  @override
  bool get available => _now.available;

  @override
  bool get topUpAvailable => _now.topUpAvailable;

  @override
  String get currency => on.currency;

  @override
  WalletBalanceRepository inCurrency(String currency) =>
      SwitchedWalletRepository(
        on: on.inCurrency(currency),
        off: off.inCurrency(currency),
        isOn: isOn,
      );

  @override
  Future<double> loadBalance() => _now.loadBalance();

  @override
  Future<double> creditTopUp({
    required String paymentIntentId,
    required double previous,
    required double amount,
  }) => _now.creditTopUp(
    paymentIntentId: paymentIntentId,
    previous: previous,
    amount: amount,
  );

  @override
  Future<double> debitRide({
    String? rideId,
    required double previous,
    required double amount,
  }) => _now.debitRide(rideId: rideId, previous: previous, amount: amount);

  @override
  Future<double> refund({required double previous, required double amount}) =>
      _now.refund(previous: previous, amount: amount);
}
