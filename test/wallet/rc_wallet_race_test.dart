import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/wallet/data/wallet_repository.dart';

/// A stored balance whose reads and writes take a turn of the event loop,
/// like SharedPreferences, so interleaved movements can race.
class _SlowStore implements WalletBalanceSource {
  _SlowStore(this.balance);

  double balance;

  @override
  Future<double> loadBalance() async {
    await Future<void>.delayed(const Duration(milliseconds: 2));
    return balance;
  }

  @override
  Future<void> saveBalance(double value) async {
    await Future<void>.delayed(const Duration(milliseconds: 2));
    balance = value;
  }
}

/// RC-10: the local ledger takes deltas against the stored balance, one
/// movement at a time, never the stale balance a page loaded earlier.
void main() {
  test('a top-up from a stale page balance keeps a ride charge that landed '
      'meanwhile', () async {
    final store = _SlowStore(100);
    final ledger = LocalWalletRepository(store);
    // The Wallet page loaded 100 kr; a 30 kr ride charge lands.
    await ledger.debitRide(rideId: 'r1', previous: 100, amount: 30);
    final next = await ledger.creditTopUp(
      paymentIntentId: 'pi_1',
      previous: 100,
      amount: 50,
    );
    expect(next, 120);
    expect(store.balance, 120);
  });

  test('concurrent movements are serialized', () async {
    final store = _SlowStore(100);
    final a = LocalWalletRepository(store);
    final b = LocalWalletRepository(store);
    await Future.wait([
      a.creditTopUp(paymentIntentId: 'pi_2', previous: 100, amount: 50),
      b.debitRide(rideId: 'r2', previous: 100, amount: 30),
      a.refund(previous: 100, amount: 12.5),
    ]);
    expect(store.balance, 132.5);
  });

  test('amounts are added in öre, without float drift', () async {
    final store = _SlowStore(0);
    final ledger = LocalWalletRepository(store);
    for (var i = 0; i < 10; i++) {
      await ledger.refund(previous: 0, amount: 0.1);
    }
    expect(store.balance, 1.0);
  });
}
