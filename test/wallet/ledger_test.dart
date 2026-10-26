import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/wallet/domain/wallet_ledger.dart';

void main() {
  test('ledger sums credits and rides', () {
    final ledger = WalletLedger();
    ledger.add(
      WalletEntry(
        id: '1',
        kind: WalletEntryKind.credit,
        amountMinor: 5000,
        at: DateTime.now(),
      ),
    );
    ledger.add(
      WalletEntry(
        id: '2',
        kind: WalletEntryKind.ride,
        amountMinor: -1200,
        at: DateTime.now(),
      ),
    );
    expect(ledger.balanceMinor, 3800);
  });
}
