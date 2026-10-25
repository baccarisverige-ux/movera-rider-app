import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/auth/token_store.dart';
import 'package:movera_rider/features/auth/data/auth_repository.dart';
import 'package:movera_rider/features/auth/domain/otp_challenge.dart';
import 'package:movera_rider/features/auth/presentation/sign_in.dart';
import 'package:movera_rider/features/ride_booking/application/ride_restore_coordinator.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RideSnapshotStore.epoch = 0;
  });

  const testEnv = AppEnv(
    flavor: AppFlavor.test,
    apiBaseUrl: 'https://api.test.movera.invalid',
  );

  test('OTP request returns session, expiry, retry window and saves no tokens', () async {
    final tokens = MemoryTokenStore();
    final auth = AuthRepository(
      api: ApiClient(
        env: testEnv,
        client: InProcessMockClient(),
        tokens: tokens,
      ),
      tokens: tokens,
    );

    final challenge = await auth.requestOtp(phone: '+46701234567');

    expect(challenge.phone, '+46701234567');
    expect(challenge.requestId, isNotEmpty);
    expect(challenge.sessionId, isNotEmpty);
    expect(challenge.expiresAt.isAfter(DateTime.now().toUtc()), isTrue);
    expect(challenge.retryAfter, greaterThan(Duration.zero));
    expect(await tokens.readAccess(), isNull);
    expect(await tokens.readRefresh(), isNull);
  });

  test('the code request names the rider app (contract OtpRequest.app)', () async {
    Map<String, dynamic>? sent;
    final tokens = MemoryTokenStore();
    final auth = AuthRepository(
      api: ApiClient(
        env: testEnv,
        client: MockClient((request) async {
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'requestId': 'req-1',
              'sessionId': 'ses-1',
              'expiresAt': DateTime.now().toUtc().add(const Duration(minutes: 5)).toIso8601String(),
              'retryAfterSeconds': 30,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
        tokens: tokens,
      ),
      tokens: tokens,
    );

    await auth.requestOtp(phone: '+46 70 123 45 67');

    expect(sent, {'phone': '+46701234567', 'app': 'rider'});
  });

  test('wrong OTP never authenticates or persists tokens', () async {
    final tokens = MemoryTokenStore();
    final auth = AuthRepository(
      api: ApiClient(
        env: testEnv,
        client: InProcessMockClient(),
        tokens: tokens,
      ),
      tokens: tokens,
    );
    final challenge = await auth.requestOtp(phone: '+46701234567');

    await expectLater(
      auth.verifyOtp(challenge: challenge, code: '9999'),
      throwsA(
        isA<ApiError>().having(
          (error) => error.detail,
          'detail',
          'invalid_otp',
        ),
      ),
    );

    expect(await tokens.readAccess(), isNull);
    expect(await tokens.readRefresh(), isNull);
  });

  test('verified OTP persists tokens only after backend success', () async {
    final tokens = MemoryTokenStore();
    final auth = AuthRepository(
      api: ApiClient(
        env: testEnv,
        client: InProcessMockClient(),
        tokens: tokens,
      ),
      tokens: tokens,
    );
    final challenge = await auth.requestOtp(phone: '+46701234567');

    await auth.verifyOtp(challenge: challenge, code: '1234');

    expect(await tokens.readAccess(), startsWith('mock-access-phone-'));
    expect(await tokens.readRefresh(), startsWith('mock-refresh-phone-'));
  });

  test('auth gate blocks Home when enabled and session is missing', () async {
    final coordinator = RideRestoreCoordinator(
      reader: () async => null,
      authRequired: () => true,
      hasSession: () async => false,
    );

    final root = await coordinator.root();

    expect(root, isA<SignIn>());
  });

  test('active ride restore requires session and keeps the snapshot', () async {
    final snapshot = RideSnapshot(
      status: RideStatus.findingDriver,
      savedAt: DateTime.now(),
      pickupAddress: 'Pickup',
      destinationAddress: 'Destination',
      pickupLat: 59.33,
      pickupLng: 18.06,
      destinationLat: 59.34,
      destinationLng: 18.08,
      rideType: 'Movera',
      price: 180,
      paymentMethod: 'card',
      rideId: 'ride_phase73',
    );
    final coordinator = RideRestoreCoordinator(
      reader: () async => snapshot,
      authRequired: () => true,
      hasSession: () async => false,
      resync: (_) async {},
    );

    await RideSnapshotStore.save(snapshot);
    expect((await RideSnapshotStore.read())?.rideId, 'ride_phase73');

    final root = await coordinator.root();

    expect(root, isA<SignIn>());
    // A reload or expired session must not lose the live ride: it is
    // re-read from the server once the rider has signed in again.
    expect((await RideSnapshotStore.read())?.rideId, 'ride_phase73');
  });

  test('a first verify reports a new rider; the same phone later does not', () async {
    final client = InProcessMockClient();
    final tokens = MemoryTokenStore();
    final auth = AuthRepository(
      api: ApiClient(env: testEnv, client: client, tokens: tokens),
      tokens: tokens,
    );

    final first = await auth.verifyOtp(
      challenge: await auth.requestOtp(phone: '+46701234567'),
      code: '1234',
    );
    final again = await auth.verifyOtp(
      challenge: await auth.requestOtp(phone: '+46701234567'),
      code: '1234',
    );

    expect(first.isNewRider, isTrue);
    expect(again.isNewRider, isFalse);
  });

  test(
    'first provider sign-in needs a phone and saves no tokens until the '
    'linked code is verified',
    () async {
      final client = InProcessMockClient();
      final tokens = MemoryTokenStore();
      final auth = AuthRepository(
        api: ApiClient(env: testEnv, client: client, tokens: tokens),
        tokens: tokens,
      );

      final result = await auth.signIn(provider: 'apple');

      expect(result, isA<ProviderPhoneRequired>());
      final link = (result as ProviderPhoneRequired).link;
      expect(link.provider, 'apple');
      expect(link.linkToken, isNotEmpty);
      expect(await tokens.readAccess(), isNull);
      expect(await tokens.readRefresh(), isNull);

      final challenge = await auth.requestOtp(phone: '+46701234567', link: link);
      expect(challenge.link, same(link));
      expect(await tokens.readAccess(), isNull);

      final verified = await auth.verifyOtp(challenge: challenge, code: '1234');
      expect(verified.isNewRider, isTrue);
      expect(await tokens.readAccess(), startsWith('mock-access-apple-'));

      // With a verified phone on file, Apple now signs straight in.
      await tokens.clear();
      expect(await auth.signIn(provider: 'apple'), isA<ProviderSignedIn>());
      expect(await tokens.readAccess(), 'mock-access-apple');
    },
  );

  test('a code request with an unknown link token is refused', () async {
    final tokens = MemoryTokenStore();
    final auth = AuthRepository(
      api: ApiClient(env: testEnv, client: InProcessMockClient(), tokens: tokens),
      tokens: tokens,
    );

    await expectLater(
      auth.requestOtp(
        phone: '+46701234567',
        link: const ProviderLink(provider: 'apple', linkToken: 'link_forged'),
      ),
      throwsA(
        isA<ApiError>()
            .having((e) => e.code, 'code', 'invalid_request')
            .having((e) => e.reason, 'reason', 'invalid_link'),
      ),
    );
  });

  test('expired OTP challenge is rejected before verify transport', () {
    final challenge = OtpChallenge(
      phone: '+46701234567',
      requestId: 'req_expired',
      sessionId: 'otp_expired',
      expiresAt: DateTime.now().toUtc().subtract(const Duration(seconds: 1)),
      retryAfter: const Duration(seconds: 30),
    );

    expect(challenge.isExpired, isTrue);
  });
}
