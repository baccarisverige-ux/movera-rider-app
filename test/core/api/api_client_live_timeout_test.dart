import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';

/// Live stability: movera-server runs on a small instance that sleeps when
/// idle and answers its first request 30-50 s later. The contract wire
/// (staging, production) waits 30 s per request; the in-process mock keeps
/// its 15 s so the demo and the tests behave as before.
void main() {
  const live = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://x.invalid',
  );
  const demo = AppEnv(flavor: AppFlavor.demo, apiBaseUrl: 'https://x.invalid');

  http.Client answersAfter(Duration wait) => MockClient(
    (_) => Future<http.Response>.delayed(wait, () => http.Response('{}', 200)),
  );

  test('the live wire waits 30 s for an answer, the mock 15 s', () {
    expect(
      ApiClient(client: answersAfter(Duration.zero), env: live).requestTimeout,
      const Duration(seconds: 30),
    );
    expect(
      ApiClient(client: answersAfter(Duration.zero), env: demo).requestTimeout,
      const Duration(seconds: 15),
    );
    expect(
      ApiClient(
        client: answersAfter(Duration.zero),
        env: live,
        requestTimeout: const Duration(seconds: 3),
      ).requestTimeout,
      const Duration(seconds: 3),
    );
  });

  test('a POST the live server answers after 20 s succeeds', () {
    fakeAsync((async) {
      final api = ApiClient(
        client: answersAfter(const Duration(seconds: 20)),
        env: live,
      );
      Object? outcome;
      api
          .post('/api/v1/quotes', body: {})
          .then(
            (v) {
              outcome = v;
            },
            onError: (Object e) {
              outcome = e;
            },
          );
      async.elapse(const Duration(seconds: 19));
      expect(outcome, isNull);
      async.elapse(const Duration(seconds: 2));
      expect(outcome, isA<Map<String, dynamic>>());
    });
  });

  test('the same POST on the mock transport still times out at 15 s', () {
    fakeAsync((async) {
      final api = ApiClient(
        client: answersAfter(const Duration(seconds: 20)),
        env: demo,
      );
      Object? outcome;
      api
          .post('/api/v1/quotes', body: {})
          .then(
            (v) {
              outcome = v;
            },
            onError: (Object e) {
              outcome = e;
            },
          );
      async.elapse(const Duration(seconds: 16));
      expect(outcome, isA<ApiError>());
      expect((outcome! as ApiError).code, 'TIMEOUT');
      async.elapse(const Duration(seconds: 10));
    });
  });

  test('a GET that never answers is tried twice, then fails as TIMEOUT', () {
    fakeAsync((async) {
      var calls = 0;
      final api = ApiClient(
        client: MockClient((_) {
          calls++;
          return Completer<http.Response>().future;
        }),
        env: live,
      );
      Object? outcome;
      api
          .get('/api/v1/rides/r')
          .then(
            (v) {
              outcome = v;
            },
            onError: (Object e) {
              outcome = e;
            },
          );
      async.elapse(const Duration(seconds: 31));
      expect(calls, 2);
      expect(outcome, isNull);
      async.elapse(const Duration(seconds: 30));
      expect(outcome, isA<ApiError>());
      expect((outcome! as ApiError).code, 'TIMEOUT');
    });
  });
}
