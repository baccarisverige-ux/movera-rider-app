import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/auth/device_identity.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Contract v0.18.138 `deviceCheck` (owner 2026-11-20 "Ok"): the code request
/// carries a stable install id and, on Android, a Play Integrity token bound
/// to app + number + install. iPhone App Attest stays off until the owner's
/// Apple account exists. Fails before v0.18.138 (no such file). The request wiring and the
/// error text land on top of the SMS sign-in branch (…-sms-r133).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(DeviceIdentity.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  Object? Function(MethodCall call) answer = (_) => 'play-token';

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    calls.clear();
    answer = (_) => 'play-token';
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      final value = answer(call);
      if (value is Exception) throw value;
      return value;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  String expectedNonce(String phone, String id) => base64Url
      .encode(
        sha256.convert(utf8.encode('movera-sms-code|rider|$phone|$id')).bytes,
      )
      .replaceAll('=', '');

  test(
    'the install id is made once, has the contract shape and is kept',
    () async {
      final a = DeviceIdentity(
        platform: TargetPlatform.android,
        isWeb: false,
        random: Random(1),
      );
      final id = await a.installId();
      expect(id, matches(RegExp(r'^[A-Za-z0-9_-]{16,64}$')));
      expect(await a.installId(), id);
      final again = DeviceIdentity(
        platform: TargetPlatform.android,
        isWeb: false,
        random: Random(2),
      );
      expect(
        await again.installId(),
        id,
        reason: 'read back from the app storage',
      );
      expect(
        (await SharedPreferences.getInstance()).getString(
          DeviceIdentity.storageKey,
        ),
        id,
      );
    },
  );

  test('Android: a Play Integrity token with the binding as nonce', () async {
    final d = DeviceIdentity(platform: TargetPlatform.android, isWeb: false);
    final fields = await d.requestFields('rider', '+46701234567');
    final id = fields['installId'] as String;
    expect(fields['deviceCheck'], {
      'platform': 'android',
      'token': 'play-token',
    });
    expect(calls.single.method, 'playIntegrity');
    expect(calls.single.arguments, {
      'nonce': expectedNonce('+46701234567', id),
    });
  });

  test(
    'iPhone: no check while App Attest is off (default); with it on, the attestation and key id',
    () async {
      expect(
        DeviceIdentity.appAttestEnabled,
        isFalse,
        reason: 'inactive until the owner\'s Apple account',
      );
      final off = DeviceIdentity(platform: TargetPlatform.iOS, isWeb: false);
      final fields = await off.requestFields('rider', '+46701234567');
      expect(fields.containsKey('deviceCheck'), isFalse);
      expect(fields['installId'], isA<String>());
      expect(calls, isEmpty);
      answer = (_) => {'attestation': 'YXR0', 'keyId': 'a2V5'};
      final on = DeviceIdentity(
        platform: TargetPlatform.iOS,
        isWeb: false,
        appAttest: true,
      );
      expect((await on.requestFields('rider', '+46701234567'))['deviceCheck'], {
        'platform': 'ios',
        'token': 'YXR0',
        'keyId': 'a2V5',
      });
      expect(calls.single.method, 'appAttest');
    },
  );

  test(
    'web, a failing or slow check: the request goes without a check',
    () async {
      expect(
        (await DeviceIdentity(
          platform: TargetPlatform.android,
          isWeb: true,
        ).requestFields('rider', '+46701234567')).containsKey('deviceCheck'),
        isFalse,
      );
      answer = (_) => PlatformException(code: 'no_play_services');
      expect(
        (await DeviceIdentity(
          platform: TargetPlatform.android,
          isWeb: false,
        ).requestFields('rider', '+46701234567')).containsKey('deviceCheck'),
        isFalse,
      );
      messenger.setMockMethodCallHandler(
        channel,
        (call) =>
            Future<Object?>.delayed(const Duration(seconds: 2), () => 'late'),
      );
      final slow = DeviceIdentity(
        platform: TargetPlatform.android,
        isWeb: false,
        timeout: const Duration(milliseconds: 50),
      );
      expect(
        (await slow.requestFields(
          'rider',
          '+46701234567',
        )).containsKey('deviceCheck'),
        isFalse,
      );
    },
  );
}
