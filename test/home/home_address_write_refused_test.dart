import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/home/data/home_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// uat-r1 (Playwright, iPhone profile with localStorage refusing writes as
/// iOS Safari can): choosing a destination on Home awaits the Recents /
/// saved-places write, so a refused write threw out of the destination
/// step and Select Ride never opened ("bugs when I click next"). The
/// addresses live in memory for this session; the device copy is best
/// effort and a refusal is logged, not thrown.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
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

  test('a refused saved-addresses write does not throw out of Home', () async {
    await expectLater(
      HomeAddressRepository().save(
        HomeAddressSnapshot(recent: const ['Stockholm Central Station']),
      ),
      completes,
    );
  });
}
