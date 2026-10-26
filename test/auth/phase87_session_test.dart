import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/auth_composition.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/auth/token_store.dart';

void main() {
  const env = AppEnv(
    flavor: AppFlavor.test,
    apiBaseUrl: 'https://api.test.movera.invalid',
    authRequired: true,
  );

  test('production defaults to auth and refuses explicit opt-out', () {
    const production = AppEnv(
      flavor: AppFlavor.production,
      apiBaseUrl: 'https://api.movera.example',
    );
    expect(production.authRequired, isTrue);
    expect(() => AuthComposition.validate(production), returnsNormally);
    expect(
      () => AuthComposition.validate(
        const AppEnv(
          flavor: AppFlavor.production,
          apiBaseUrl: 'https://api.movera.example',
          authRequired: false,
        ),
      ),
      throwsStateError,
    );
  });

  test(
    '401 refreshes exactly once and retries with same idempotency key',
    () async {
      final tokens = MemoryTokenStore();
      await tokens.save(access: 'expired', refresh: 'original-refresh');
      var refreshes = 0;
      var writes = 0;
      final api = ApiClient(
        env: env,
        tokens: tokens,
        client: MockClient((request) async {
          if (request.url.path == '/api/v1/auth/refresh') {
            refreshes++;
            expect(
              jsonDecode(request.body)['refreshToken'],
              'original-refresh',
            );
            return http.Response(
              jsonEncode({'accessToken': 'fresh', 'refreshToken': 'rotated'}),
              200,
            );
          }
          writes++;
          expect(request.headers['Idempotency-Key'], 'one-operation');
          return http.Response(
            request.headers['Authorization'] == 'Bearer fresh'
                ? '{"ok":true}'
                : '{}',
            request.headers['Authorization'] == 'Bearer fresh' ? 200 : 401,
          );
        }),
      );

      expect(
        (await api.post(
          '/ride',
          body: {'x': 1},
          idempotencyKey: 'one-operation',
        ))['ok'],
        true,
      );
      expect(refreshes, 1);
      expect(writes, 2);
      expect(await tokens.readRefresh(), 'rotated');
    },
  );

  test('failed refresh clears credentials and signals sign-in', () async {
    final tokens = MemoryTokenStore();
    await tokens.save(access: 'expired', refresh: 'invalid');
    var expired = 0;
    final api = ApiClient(
      env: env,
      tokens: tokens,
      onSessionExpired: () async {
        expired++;
      },
      client: MockClient((request) async => http.Response('{}', 401)),
    );
    await expectLater(
      api.get('/ride'),
      throwsA(
        isA<ApiError>().having((error) => error.statusCode, 'status', 401),
      ),
    );
    expect(await tokens.readAccess(), isNull);
    expect(await tokens.readRefresh(), isNull);
    expect(expired, 1);
  });

  test('public OTP 401 does not redirect or refresh', () async {
    var expired = 0;
    var calls = 0;
    final api = ApiClient(
      env: env,
      tokens: MemoryTokenStore(),
      onSessionExpired: () async {
        expired++;
      },
      client: MockClient((request) async {
        calls++;
        return http.Response('{"code":"INVALID_OTP"}', 401);
      }),
    );
    await expectLater(
      api.post('/api/v1/auth/otp/verify'),
      throwsA(isA<ApiError>()),
    );
    expect(calls, 1);
    expect(expired, 0);
  });
}
