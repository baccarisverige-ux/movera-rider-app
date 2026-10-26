import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/feature_flags/feature_flags.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/wallet/data/wallet_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  RideSelectionController controller() =>
      RideSelectionController(flags: const FeatureFlags());

  test('the wallet covers part of the fare and the method pays the rest', () {
    final c = controller()..setWalletBalance(50);
    expect(c.walletAppliedKr(200), 50);
    expect(c.remainderKr(200), 150);
  });

  test('a balance larger than the fare covers it all', () {
    final c = controller()..setWalletBalance(300);
    expect(c.walletAppliedKr(200), 200);
    expect(c.remainderKr(200), 0);
  });

  test('switched off, the wallet is not touched', () {
    final c = controller()
      ..setWalletBalance(50)
      ..useWalletFirst = false;
    expect(c.walletAppliedKr(200), 0);
    expect(c.remainderKr(200), 200);
  });

  test('an empty wallet changes nothing', () {
    final c = controller();
    expect(c.walletAppliedKr(200), 0);
  });

  test('the setting is remembered and on by default', () async {
    final store = WalletStore();
    expect((await store.loadPayments()).useWalletFirst, isTrue);
    await store.savePayments(
      WalletPaymentSettings(
        defaultMethod: 'cash',
        business: false,
        useWalletFirst: false,
      ),
    );
    expect((await store.loadPayments()).useWalletFirst, isFalse);
  });

  test('the demo seed never overwrites a stored balance', () async {
    SharedPreferences.setMockInitialValues({WalletStore.balanceKey: 12.0});
    await WalletStore.seedDemoBalance();
    expect(await WalletStore().loadBalance(), 12);
    SharedPreferences.setMockInitialValues({});
    await WalletStore.seedDemoBalance();
    expect(await WalletStore().loadBalance(), 50);
  });
}
