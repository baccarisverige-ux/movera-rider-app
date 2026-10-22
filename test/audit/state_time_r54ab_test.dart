import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/auth/token_store.dart';

/// Wave 5 R5.4 parts a + b: state and time (low). One test per bug.
const _env = AppEnv(flavor: AppFlavor.staging, apiBaseUrl: 'https://x.invalid');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('rider-6: a wrong OTP with an old token left is a wrong code, not an '
      'expired session', () async {
    final tokens = MemoryTokenStore();
    await tokens.save(access: 'old-access', refresh: 'mock-refresh-1');
    var expired = 0;
    var refreshes = 0;
    final api = ApiClient(
      env: _env,
      tokens: tokens,
      onSessionExpired: () async => expired++,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/auth/refresh')) {
          refreshes++;
          return http.Response(
            jsonEncode({'accessToken': 'new', 'refreshToken': 'r2'}),
            200,
          );
        }
        return http.Response(jsonEncode({'code': 'invalid_otp'}), 401);
      }),
    );
    await expectLater(
      api.post('/api/v1/auth/otp/verify', body: {'code': '000000'}),
      throwsA(isA<ApiError>().having((e) => e.code, 'code', 'invalid_otp')),
    );
    expect(expired, 0);
    expect(refreshes, 0);
    expect(await tokens.readAccess(), 'old-access');
  });
}
