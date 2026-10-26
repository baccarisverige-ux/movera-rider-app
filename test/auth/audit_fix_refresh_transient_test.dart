import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/auth/token_store.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ARCH-2: only a definitive refresh rejection ends the session; a network
/// failure keeps the tokens, and expiry keeps the live ride.
const env = AppEnv(flavor: AppFlavor.staging, apiBaseUrl: 'https://x.invalid');

Future<(ApiClient, MemoryTokenStore, List<int>)> _client(
  Future<http.Response> Function(http.Request request) refresh,
) async {
  final tokens = MemoryTokenStore();
  await tokens.save(access: 'a1', refresh: 'r1');
  final expired = <int>[0];
  final api = ApiClient(
    env: env,
    tokens: tokens,
    onSessionExpired: () async => expired[0]++,
    client: MockClient((request) async {
      if (request.url.path.endsWith('/auth/refresh')) return refresh(request);
      return http.Response(jsonEncode({'code': 'UNAUTHORIZED'}), 401);
    }),
  );
  return (api, tokens, expired);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a network error during refresh keeps the session', () async {
    final (api, tokens, expired) = await _client(
      (_) async => throw http.ClientException('offline'),
    );
    await expectLater(
      api.get('/api/v1/rides/ride_1'),
      throwsA(isA<ApiError>().having((e) => e.code, 'code', 'NETWORK')),
    );
    expect(expired[0], 0);
    expect(await tokens.readRefresh(), 'r1');
    expect(await tokens.readAccess(), 'a1');
  });

  test('a 5xx from the refresh endpoint keeps the session', () async {
    final (api, tokens, expired) = await _client(
      (_) async => http.Response('{"code":"DOWN"}', 503),
    );
    await expectLater(
      api.get('/api/v1/rides/ride_1'),
      throwsA(isA<ApiError>().having((e) => e.isRetryable, 'retryable', true)),
    );
    expect(expired[0], 0);
    expect(await tokens.readRefresh(), 'r1');
  });

  test(
    'a rejected refresh expires the session once for concurrent 401s',
    () async {
      final (api, tokens, expired) = await _client(
        (_) async => http.Response('{"code":"INVALID_REFRESH"}', 401),
      );
      await Future.wait([
        api.get('/api/v1/rides/ride_1').then((_) {}, onError: (_) {}),
        api.get('/api/v1/rides/ride_2').then((_) {}, onError: (_) {}),
        api.get('/api/v1/rides/ride_3').then((_) {}, onError: (_) {}),
      ]);
      expect(expired[0], 1);
      expect(await tokens.readRefresh(), isNull);
    },
  );

  test('session expiry in the composed app keeps the live ride', () async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await RideSnapshotStore.save(
      RideSnapshot(
        status: RideStatus.driverArriving,
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
        rideId: 'ride_arch2',
      ),
    );
    await AppScope.instance.tokens.save(
      access: 'arch2-expired-access',
      refresh: 'arch2-rejected-refresh',
    );
    await expectLater(
      AppScope.instance.api.post(
        '/api/v1/auth/refresh',
        body: {'refreshToken': 'arch2-rejected-refresh'},
      ),
      throwsA(isA<ApiError>()),
    );
    expect(await AppScope.instance.tokens.readAccess(), isNull);
    expect((await RideSnapshotStore.read())?.rideId, 'ride_arch2');
  });
}
