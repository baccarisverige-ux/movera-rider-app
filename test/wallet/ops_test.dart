import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/payments/mock_payment_gateway.dart';
import 'package:movera_rider/features/wallet/application/wallet_controller.dart';
import 'package:movera_rider/features/wallet/data/wallet_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemWallet extends WalletStore {
  double balance = 0;

  @override
  Future<double> loadBalance() async => balance;

  @override
  Future<void> saveBalance(double value) async {
    balance = value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'legacy local voucher values are purged during wallet restore',
    () async {
      SharedPreferences.setMockInitialValues({
        'movera_voucher_code': 'LEGACY',
        'movera_voucher_amount': 100,
        'movera_voucher_expires': '2027-01-01',
        'movera_used_vouchers': '["LEGACY"]',
      });

      await WalletStore().loadPayments();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('movera_voucher_code'), isFalse);
      expect(prefs.containsKey('movera_voucher_amount'), isFalse);
      expect(prefs.containsKey('movera_voucher_expires'), isFalse);
      expect(prefs.containsKey('movera_used_vouchers'), isFalse);
    },
  );

  test('legacy unverified payment labels and defaults are removed', () async {
    SharedPreferences.setMockInitialValues({
      'movera_payment_methods': '[{"id":"card_4242","title":"Card ending 4242","detail":"Debit or credit card"},{"id":"paypal","detail":"Connected"}]',
      'movera_default_payment': 'card_4242',
    });
    final store = WalletStore();
    final settings = await store.loadPayments();
    expect(settings.extraMethods, isEmpty);
    expect(settings.defaultMethod, 'cash');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('movera_payment_methods'), isFalse);
    expect(prefs.getString('movera_default_payment'), 'cash');

    await store.savePayments(
      WalletPaymentSettings(
        defaultMethod: 'paypal',
        business: false,
        extraMethods: [
          {'id': 'paypal', 'detail': 'Connected'},
        ],
      ),
    );
    expect((await store.loadPayments()).defaultMethod, 'cash');
    expect(prefs.containsKey('movera_payment_methods'), isFalse);
  });

  test('top-up idempotency key reused', () async {
    final gw = MockPaymentGateway();
    final a = await gw.create(
      amountMinor: 20000,
      currency: 'SEK',
      idempotencyKey: 'same',
    );
    final b = await gw.create(
      amountMinor: 20000,
      currency: 'SEK',
      idempotencyKey: 'same',
    );
    expect(a.id, b.id);
  });

  test('supported wallet operations remain separate', () async {
    final store = _MemWallet()..balance = 50;
    final wallet = WalletController(store: store);
    final topped = await wallet.topUp(previous: 50, amount: 200);
    expect((topped as TopUpCredited).balance, 250);
    final charged = await wallet.chargeRide(previous: 250, amount: 80);
    expect(charged, 170);
    final refunded = await wallet.refund(previous: 170, amount: 80);
    expect(refunded, 250);
  });

  test('top-up same idempotency key does not double credit', () async {
    final store = _MemWallet();
    final wallet = WalletController(store: store);
    final a = await wallet.topUp(
      previous: 0,
      amount: 100,
      idempotencyKey: 'top-1',
    );
    final b = await wallet.topUp(
      previous: (a as TopUpCredited).balance,
      amount: 100,
      idempotencyKey: 'top-1',
    );
    expect(a.balance, 100);
    expect((b as TopUpCredited).balance, 100);
  });
}
