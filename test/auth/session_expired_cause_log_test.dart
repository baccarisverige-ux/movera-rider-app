import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/auth/token_store.dart';
import 'package:movera_rider/core/observability/observability.dart';

const _env = AppEnv(flavor: AppFlavor.staging, apiBaseUrl: 'https://x.invalid');

class _Logs implements LoggerSink {
  final expired = <Map<String, Object?>>[];

  @override
  void log(
    TelemetryLevel level,
    String event, {
    Map<String, Object?> extra = const {},
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (event == 'auth.session_expired') expired.add(Map.of(extra));
  }
}

Future<List<Map<String, Object?>>> _expireWith({
  required http.Response Function() refresh,
  required int retryStatus,
}) async {
  final logs = _Logs();
  Observability.configure(loggerSink: logs);
  final tokens = MemoryTokenStore();
  await tokens.save(access: 'a1', refresh: 'r1');
  final api = ApiClient(
    env: _env,
    tokens: tokens,
    onSessionExpired: () async {},
    client: MockClient((request) async {
      if (request.url.path.endsWith('/auth/refresh')) return refresh();
      final retried = request.headers['Authorization'] == 'Bearer a2';
      return http.Response(
        jsonEncode({'code': 'UNAUTHORIZED'}),
        retried ? retryStatus : 401,
      );
    }),
  );
  await api.get('/api/v1/rides/r').then((_) {}, onError: (_) {});
  return logs.expired;
}

/// Why a session ended is logged (no tokens), so a real sign-out can be
/// told apart from a reload that lost the session.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(Observability.reset);
  tearDown(Observability.reset);

  for (final status in [400, 401, 403]) {
    test('refresh $status is logged as the cause', () async {
      final logs = await _expireWith(
        refresh: () => http.Response('{"code":"INVALID_REFRESH"}', status),
        retryStatus: 200,
      );
      expect(logs, [
        {'cause': 'refresh_$status'},
      ]);
    });
  }

  test('a 401 on the retried request is logged as retry_401', () async {
    final logs = await _expireWith(
      refresh: () => http.Response(
        jsonEncode({'accessToken': 'a2', 'refreshToken': 'r2'}),
        200,
      ),
      retryStatus: 401,
    );
    expect(logs, [
      {'cause': 'retry_401'},
    ]);
    expect(logs.single.values.join(), isNot(contains('a2')));
  });
}
