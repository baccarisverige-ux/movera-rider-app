import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/app/bootstrap.dart';
import 'package:movera_rider/features/wallet/data/wallet_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// uat-r1: on iOS Safari a preference write can be refused (Private
/// Browsing on older iOS, a full origin, "Block All Cookies"). One such
/// refusal in a step awaited before runApp left the rider on the MOVERA
/// boot screen for ever, which reads as "the app crashed". A boot step that
/// touches storage is logged and skipped; the boot goes on.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // The device store refuses every write, as Safari's localStorage does.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/shared_preferences'),
      (call) async {
        if (call.method == 'getAll') return <String, Object>{};
        throw PlatformException(code: 'QuotaExceededError');
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/shared_preferences'),
      null,
    );
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('a refused demo wallet seed does not stop the boot', () async {
    // The failure is real: the seed itself is refused by the store.
    await expectLater(WalletStore.seedDemoBalance(), throwsA(anything));
    // The boot step around it absorbs it and completes.
    var continued = false;
    await bootStep('wallet.seed', WalletStore.seedDemoBalance);
    continued = true;
    expect(continued, isTrue);
  });

  test('a boot step that throws is logged, the next step still runs',
      () async {
    final ran = <String>[];
    await bootStep('first', () async {
      ran.add('first');
      throw StateError('storage refused');
    });
    await bootStep('second', () async => ran.add('second'));
    expect(ran, ['first', 'second']);
  });
}
