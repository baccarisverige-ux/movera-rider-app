import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/app_update_policy.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/auth/token_store.dart';

void main() {
  const env = AppEnv(
    flavor: AppFlavor.test,
    apiBaseUrl: 'https://api.movera.test',
  );

  test(
    '401 preserves server error metadata and clears invalid session',
    () async {
      final tokens = MemoryTokenStore();
      await tokens.save(access: 'expired', refresh: 'refresh');
      final api = ApiClient(
        env: env,
        tokens: tokens,
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({'code': 'SESSION_EXPIRED', 'message': 'Sign in again'}),
            401,
            headers: {'retry-after': '7'},
          ),
        ),
      );

      try {
        await api.get('/api/v1/profile');
        fail('expected ApiError');
      } on ApiError catch (error) {
        expect(error.statusCode, 401);
        expect(error.code, 'SESSION_EXPIRED');
        expect(error.message, 'Sign in again');
        expect(error.retryAfter, const Duration(seconds: 7));
        expect(error.isAuthenticationFailure, isTrue);
      }
      expect(await tokens.readAccess(), isNull);
      expect(await tokens.readRefresh(), isNull);
    },
  );

  test('403 is an authentication failure but not retryable', () {
    const error = ApiError(
      code: 'FORBIDDEN',
      message: 'Forbidden',
      statusCode: 403,
    );
    expect(error.isAuthenticationFailure, isTrue);
    expect(error.isRetryable, isFalse);
  });

  test(
    'force update is driven by minimum build config, not hardcoded date',
    () {
      expect(
        AppUpdatePolicy.fromConfig({
          'minimumBuild': 12,
        }, currentBuild: 11).requiresUpdate,
        isTrue,
      );
      expect(
        AppUpdatePolicy.fromConfig({
          'minimumBuild': 12,
        }, currentBuild: 12).requiresUpdate,
        isFalse,
      );
      expect(
        AppUpdatePolicy.fromConfig({}, currentBuild: 1).requiresUpdate,
        isFalse,
      );
    },
  );
}
