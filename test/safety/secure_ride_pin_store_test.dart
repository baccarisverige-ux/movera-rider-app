import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/safety/data/safety_data_sources.dart';
import 'package:movera_rider/features/safety/data/secure_ride_pin_store.dart';
import 'package:movera_rider/features/safety/domain/ride_pin.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'on a native-secure platform, the PIN never touches plaintext SharedPreferences',
    () async {
      final pinStore = SecureRidePinStore.fake();
      final local = PreferencesSafetyLocalDataSource(pinStore: pinStore);

      final cache = await local.load();
      expect(cache.pin.isAvailable, isFalse);
      cache.pin = RidePin.fromJson({'pinId': 'issued', 'pin': '4242'});
      final realPin = cache.pin.pin;
      expect(RegExp(r'^\d{4}$').hasMatch(realPin), isTrue);

      await local.save(cache);

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(PreferencesSafetyLocalDataSource.cacheKey);
      expect(raw, isNotNull);
      final decoded = jsonDecode(raw!) as Map<String, dynamic>;
      final persistedPin = (decoded['pin'] as Map)['pin'];
      expect(
        persistedPin,
        isNot(realPin),
        reason: 'the real PIN must not be written to plaintext prefs',
      );

      expect(await pinStore.read(), realPin);
    },
  );

  test(
    'reloading a native-secure store restores the real PIN from secure storage',
    () async {
      final pinStore = SecureRidePinStore.fake();
      final first = PreferencesSafetyLocalDataSource(pinStore: pinStore);
      final cache = await first.load();
      cache.pin = RidePin.fromJson({'pinId': 'issued', 'pin': '4242'});
      await first.save(cache);
      final realPin = cache.pin.pin;

      final second = PreferencesSafetyLocalDataSource(pinStore: pinStore);
      final reloaded = await second.load();

      expect(reloaded.pin.pin, realPin);
      expect(reloaded.pin.pinId, cache.pin.pinId);
    },
  );

  test(
    'migrates an existing plaintext-PIN cache into secure storage on first load',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        PreferencesSafetyLocalDataSource.cacheKey,
        jsonEncode({
          'preferences': const {},
          'pin': {
            'pinId': 'pin_legacy',
            'userId': 'rider-local',
            'pin': '4242',
            'required': false,
            'version': 1,
            'serverAuthoritative': true,
          },
          'contacts': [],
          'shares': {},
          'rideCheck': const {},
          'events': [],
          'recordings': [],
        }),
      );

      final pinStore = SecureRidePinStore.fake();
      final local = PreferencesSafetyLocalDataSource(pinStore: pinStore);
      final cache = await local.load();

      expect(cache.pin.pin, '4242');
      expect(await pinStore.read(), '4242');

      final raw = prefs.getString(PreferencesSafetyLocalDataSource.cacheKey);
      final decoded = jsonDecode(raw!) as Map<String, dynamic>;
      expect((decoded['pin'] as Map)['pin'], isNot('4242'));
    },
  );

  test('memoryOnly stores never touch the secure pin store', () async {
    final pinStore = SecureRidePinStore.fake();
    final local = PreferencesSafetyLocalDataSource(
      memoryOnly: true,
      pinStore: pinStore,
    );
    final cache = await local.load();
    await local.save(cache);

    expect(await pinStore.read(), isNull);
  });
}
