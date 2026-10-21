import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/auth/token_store.dart';
import 'package:movera_rider/features/auth/application/fresh_install_reset.dart';
import 'package:movera_rider/features/auth/application/user_data_wipe.dart';
import 'package:movera_rider/features/safety/data/secure_ride_pin_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// rider-u17: iOS keeps Keychain items after an uninstall but drops
/// SharedPreferences, so a new install found the previous owner's tokens
/// and signed in as them.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(MemoryTokenStore, SecureRidePinStore)> leftovers() async {
    final tokens = MemoryTokenStore();
    await tokens.save(access: 'owner-a-access', refresh: 'owner-a-refresh');
    final pin = SecureRidePinStore.fake();
    await pin.write('4321');
    return (tokens, pin);
  }

  test('a new install clears the session and PIN the Keychain kept', () async {
    SharedPreferences.setMockInitialValues({});
    final (tokens, pin) = await leftovers();

    expect(await FreshInstallReset.run(tokens: tokens, pin: pin), isTrue);

    expect(await tokens.readAccess(), isNull);
    expect(await tokens.readRefresh(), isNull);
    expect(await pin.read(), isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(FreshInstallReset.markerKey), isTrue);
  });

  test('later launches of the same install keep the session', () async {
    SharedPreferences.setMockInitialValues({});
    final (tokens, pin) = await leftovers();
    await FreshInstallReset.run(tokens: tokens, pin: pin);
    await tokens.save(access: 'rider-b-access', refresh: 'rider-b-refresh');
    await pin.write('1111');

    expect(await FreshInstallReset.run(tokens: tokens, pin: pin), isFalse);

    expect(await tokens.readAccess(), 'rider-b-access');
    expect(await pin.read(), '1111');
  });

  test('an update from a version without the marker stays signed in', () async {
    SharedPreferences.setMockInitialValues({
      'movera_onboarding_done': true,
      UserDataWipe.riderFingerprintKey: '0123456789abcdef',
    });
    final (tokens, pin) = await leftovers();

    expect(await FreshInstallReset.run(tokens: tokens, pin: pin), isFalse);

    expect(await tokens.readAccess(), 'owner-a-access');
    expect(await pin.read(), '4321');
  });

  test('sign-out keeps the marker: it belongs to the install', () {
    expect(UserDataWipe.deviceKeys, contains(FreshInstallReset.markerKey));
  });
}
