import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/auth/application/user_data_wipe.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/safety/data/secure_ride_pin_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Rules audits/impact/rider-wipe-partway.md, Round 2 (supervisor SF-2,
/// SF-4 a): the ride PIN delete failing. A phone whose secure storage
/// answers nothing at all holds no readable PIN, so the wipe is not held
/// up; a PIN that is still readable keeps the previous rider recorded.

const _channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

/// The phone's secure storage: [pin] is what a read answers; a delete
/// throws [deleteFailures] times before it works.
class _Keychain {
  String? pin = '4821';
  int deleteFailures = 0;
  bool readThrows = false;
  int deletes = 0;

  Future<Object?> call(MethodCall call) async {
    switch (call.method) {
      case 'read':
        if (readThrows) throw PlatformException(code: 'keychain');
        return pin;
      case 'delete':
        deletes += 1;
        if (deleteFailures > 0) {
          deleteFailures -= 1;
          throw PlatformException(code: 'keychain');
        }
        pin = null;
        return null;
    }
    return null;
  }
}

_Keychain _install() {
  final keychain = _Keychain();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(_channel, keychain.call);
  addTearDown(() => messenger.setMockMethodCallHandler(_channel, null));
  return keychain;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'delete throws and nothing can be read back: counted as removed',
    () async {
      final keychain = _install()
        ..deleteFailures = 99
        ..readThrows = true;
      expect(await const SecureRidePinStore().clear(), isTrue);
      expect(keychain.deletes, 1);
    },
  );

  test('delete throws and no PIN is saved: counted as removed', () async {
    final keychain = _install()
      ..deleteFailures = 99
      ..pin = null;
    expect(await const SecureRidePinStore().clear(), isTrue);
    expect(keychain.deletes, 1);
  });

  test(
    'delete throws once with the PIN still readable: tried once more',
    () async {
      final keychain = _install()..deleteFailures = 1;
      expect(await const SecureRidePinStore().clear(), isTrue);
      expect(keychain.deletes, 2);
      expect(keychain.pin, isNull);
    },
  );

  test(
    'delete keeps throwing with the PIN still readable: not removed',
    () async {
      final keychain = _install()..deleteFailures = 99;
      expect(await const SecureRidePinStore().clear(), isFalse);
      expect(keychain.deletes, 2);
      expect(keychain.pin, '4821');
    },
  );

  test(
    'wipe: a ride PIN that stays readable keeps the previous rider '
    'recorded and refuses the next rider; an unreadable one does not',
    () async {
      SharedPreferences.setMockInitialValues({'movera_home_address': 'A home'});
      RideSnapshotStore.epoch = 0;
      final keychain = _install()..deleteFailures = 99;
      await UserDataWipe.enterSessionAs('phone:+46701234567');
      final prefs = await SharedPreferences.getInstance();
      final ownerA = prefs.getString(UserDataWipe.riderFingerprintKey);

      await expectLater(
        UserDataWipe.enterSessionAs('phone:+46701740650'),
        throwsA(isA<UserDataWipeIncomplete>()),
      );
      expect(prefs.getString(UserDataWipe.riderFingerprintKey), ownerA);
      expect(keychain.pin, '4821');

      // The same storage, now answering nothing: no PIN can leak.
      keychain.readThrows = true;
      expect(await UserDataWipe.enterSessionAs('phone:+46701740650'), isTrue);
      expect(prefs.getString(UserDataWipe.riderFingerprintKey), isNot(ownerA));
      expect(prefs.getString('movera_home_address'), isNull);
    },
  );
}
