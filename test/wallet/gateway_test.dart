import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/payments/mock_payment_gateway.dart';
import 'package:movera_rider/features/wallet/domain/wallet_ledger.dart';

void main() {
  test('successful top-up intent', () async {
    final gw = MockPaymentGateway();
    final intent = await gw.create(
      amountMinor: 10000,
      currency: 'SEK',
      idempotencyKey: 'wallet-1',
    );
    expect(await gw.confirm(intent.id), 'succeeded');
  });

  test('failed top-up is injectable', () async {
    final gw = MockPaymentGateway()..failNext = true;
    expect(
      () => gw.create(
        amountMinor: 10000,
        currency: 'SEK',
        idempotencyKey: 'wallet-fail',
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('duplicate payment key returns the same intent', () async {
    final gw = MockPaymentGateway();
    final first = await gw.create(
      amountMinor: 5000,
      currency: 'SEK',
      idempotencyKey: 'dup',
    );
    final second = await gw.create(
      amountMinor: 5000,
      currency: 'SEK',
      idempotencyKey: 'dup',
    );
    expect(second.id, first.id);
    expect(second.amountMinor, 5000);
  });

  test('a reused key returns its own intent, not the newest one', () async {
    final gw = MockPaymentGateway();
    final a = await gw.create(
      amountMinor: 10000,
      currency: 'SEK',
      idempotencyKey: 'key-a',
    );
    final b = await gw.create(
      amountMinor: 20000,
      currency: 'SEK',
      idempotencyKey: 'key-b',
    );
    expect(b.id, isNot(a.id));
    final retryA = await gw.create(
      amountMinor: 10000,
      currency: 'SEK',
      idempotencyKey: 'key-a',
    );
    expect(retryA.id, a.id);
    expect(retryA.amountMinor, 10000);
  });

  test('ledger calculation', () {
    final ledger = WalletLedger();
    ledger.add(
      WalletEntry(
        id: '1',
        kind: WalletEntryKind.credit,
        amountMinor: 20000,
        at: DateTime(2026),
      ),
    );
    ledger.add(
      WalletEntry(
        id: '2',
        kind: WalletEntryKind.ride,
        amountMinor: -5000,
        at: DateTime(2026, 1, 2),
      ),
    );
    expect(ledger.balanceMinor, 15000);
  });
}
