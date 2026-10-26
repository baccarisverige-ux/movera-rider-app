import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/safety/data/safety_data_sources.dart';
import 'package:movera_rider/features/safety/data/secure_ride_pin_store.dart';
import 'package:movera_rider/features/safety/domain/ride_pin.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Batch 9 Phase 107 — P-06 (web half): the ride PIN digits must never be
/// written into the localStorage-backed safety cache on web.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SecureRidePinStore.debugResetWebMemory();
  });

  Future<Object?> persistedPin() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(PreferencesSafetyLocalDataSource.cacheKey);
    if (raw == null) return null;
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return (decoded['pin'] as Map)['pin'];
  }

  test('web: saving a PIN keeps the digits out of browser storage', () async {
    const pinStore = SecureRidePinStore.web();
    expect(pinStore.keepsPinOutOfPreferences, isTrue);
    final local = PreferencesSafetyLocalDataSource(pinStore: pinStore);
    final cache = await local.load();
    cache.pin = RidePin.fromJson({'pinId': 'issued', 'pin': '4242'});
    await local.save(cache);

    expect(await persistedPin(), isNot('4242'));
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(PreferencesSafetyLocalDataSource.cacheKey),
      isNot(contains('4242')),
    );
    // Same page session: the in-memory copy is still available.
    final again = await PreferencesSafetyLocalDataSource(
      pinStore: pinStore,
    ).load();
    expect(again.pin.pin, '4242');
  });

  test(
    'web: a reload forgets the PIN instead of restoring it from disk',
    () async {
      const pinStore = SecureRidePinStore.web();
      final local = PreferencesSafetyLocalDataSource(pinStore: pinStore);
      final cache = await local.load();
      cache.pin = RidePin.fromJson({'pinId': 'issued', 'pin': '4242'});
      await local.save(cache);

      SecureRidePinStore.debugResetWebMemory(); // new page session
      final reloaded = await PreferencesSafetyLocalDataSource(
        pinStore: pinStore,
      ).load();
      expect(reloaded.pin.isAvailable, isFalse);
      expect(reloaded.pin.pinId, 'issued');
    },
  );

  test('web: a legacy plaintext cache is scrubbed on first load', () async {
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

    await PreferencesSafetyLocalDataSource(
      pinStore: const SecureRidePinStore.web(),
    ).load();

    expect(await persistedPin(), isNot('4242'));
  });
}
