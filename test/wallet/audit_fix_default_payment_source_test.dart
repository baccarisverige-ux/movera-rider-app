// rider-u232: in release the Payments tab read and wrote the default method
// in local prefs while Select Ride used the server default, so the choice
// made on the tab was ignored at booking.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/observability/observability.dart';
import 'package:movera_rider/features/payments/data/default_payment_store.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/wallet/application/wallet_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(Observability.reset);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the Payments tab shows the default Select Ride uses', () async {
    // The server says Apple Pay; the device prefs say nothing (Cash).
    final server = MemoryDefaultPaymentStore('apple');
    final wallet = WalletController(defaultPayment: server);
    expect((await wallet.loadPayments()).defaultMethod, 'apple');
  });

  test(
    'a default picked on the Payments tab is the one Select Ride books',
    () async {
      // G8: no Google Pay; Apple Pay on an iPhone.
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final server = MemoryDefaultPaymentStore('cash');
      final wallet = WalletController(defaultPayment: server);
      final settings = await wallet.loadPayments();
      await wallet.savePayments(
        WalletPaymentSettings(
          defaultMethod: 'apple',
          business: settings.business,
        ),
      );
      expect(server.value, 'apple');

      final selection = RideSelectionController(paymentStore: server);
      await selection.restoreDefaultPayment();
      expect(selection.selectedPaymentItem()?.brand, 'apple');
    },
  );

  test('the wallet of another currency uses the same default', () async {
    final server = MemoryDefaultPaymentStore('apple');
    final wallet = WalletController(defaultPayment: server).forCurrency('EUR');
    expect((await wallet.loadPayments()).defaultMethod, 'apple');
  });

  test('release builds give the wallet the composed default store', () {
    const production = AppEnv(
      flavor: AppFlavor.production,
      apiBaseUrl: 'https://api.movera.example',
    );
    final scope = AppScope.composeForEnvironment(production);
    addTearDown(scope.disposeForTest);
    expect(
      identical(scope.walletController.defaultPayment, scope.defaultPayment),
      isTrue,
    );
  });
}
