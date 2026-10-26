import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/location/app_geocoding.dart';
import 'package:movera_rider/core/location/geocoding_repository.dart';
import 'package:movera_rider/core/maps/geo_point.dart';

/// Live stability: the address screen and the pin on the map ask the
/// server for addresses. On the live server (slow, sleeps when idle) a
/// lookup can take a while or be refused once while it wakes; neither is
/// a reason to tell the rider that Movera could not be reached.
void main() {
  const live = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://x.invalid',
  );
  final found = jsonEncode({
    'address': 'Medborgarplatsen, Stockholm',
    'latitude': 59.3143,
    'longitude': 18.0735,
  });

  AppGeocoding geocoding(
    Future<http.Response> Function(http.Request) handle, {
    Duration retryDelay = Duration.zero,
  }) => AppGeocoding(
    api: ApiClient(client: MockClient(handle), env: live),
    retryDelay: retryDelay,
  );

  test('a live lookup may take 25 s; the mock keeps its 8 s and no retry', () {
    const demo = AppEnv(
      flavor: AppFlavor.demo,
      apiBaseUrl: 'https://x.invalid',
    );
    final onLive = AppGeocoding(
      api: ApiClient(
        client: MockClient((_) async => http.Response('{}', 200)),
        env: live,
      ),
    );
    expect(onLive.requestTimeout, const Duration(seconds: 25));
    expect(onLive.retries, 1);
    final onMock = AppGeocoding(
      api: ApiClient(
        client: MockClient((_) async => http.Response('{}', 200)),
        env: demo,
      ),
    );
    expect(onMock.requestTimeout, const Duration(seconds: 8));
    expect(onMock.retries, 0);
    expect(AppGeocoding().requestTimeout, const Duration(seconds: 8));
  });

  test('an answer after 20 s is an answer, not a failure', () {
    fakeAsync((async) {
      final geo = geocoding(
        (_) => Future.delayed(
          const Duration(seconds: 20),
          () => http.Response(found, 200),
        ),
      );
      Object? outcome;
      geo
          .forward('Medborgarplatsen')
          .then(
            (v) {
              outcome = v;
            },
            onError: (Object e) {
              outcome = e;
            },
          );
      async.elapse(const Duration(seconds: 19));
      expect(outcome, isNull, reason: 'still waiting, no error yet');
      async.elapse(const Duration(seconds: 2));
      expect(outcome, isA<PlaceResult>());
      expect((outcome! as PlaceResult).address, 'Medborgarplatsen, Stockholm');
    });
  });

  test('a 503 while the server wakes is asked once more', () async {
    var calls = 0;
    final geo = geocoding((_) async {
      calls++;
      return calls == 1
          ? http.Response('{"code":"unavailable"}', 503)
          : http.Response(found, 200);
    });
    final place = await geo.forward('Medborgarplatsen');
    expect(calls, 2);
    expect(place?.point.latitude, 59.3143);
    expect(place?.point.longitude, 18.0735);
  });

  test('a reverse lookup retries a dropped connection once', () async {
    var calls = 0;
    final geo = geocoding((_) async {
      calls++;
      if (calls == 1) throw http.ClientException('connection reset');
      return http.Response(jsonEncode({'address': 'Sergels torg'}), 200);
    });
    expect(await geo.reverse(const GeoPoint(59.3326, 18.0649)), 'Sergels torg');
    expect(calls, 2);
  });

  test(
    'a definite refusal (4xx) and a second fault are not retried again',
    () async {
      var calls = 0;
      final refused = geocoding((_) async {
        calls++;
        return http.Response('{"code":"invalid_request"}', 400);
      });
      await expectLater(refused.forward('x'), throwsA(isA<ApiError>()));
      expect(calls, 1);

      calls = 0;
      final down = geocoding((_) async {
        calls++;
        return http.Response('{"code":"unavailable"}', 503);
      });
      await expectLater(down.forward('y'), throwsA(isA<ApiError>()));
      expect(calls, 2, reason: 'one retry, then the failure is reported');
    },
  );

  test('a timeout is not retried: the rider has waited long enough', () {
    fakeAsync((async) {
      var calls = 0;
      final geo = geocoding((_) {
        calls++;
        return Completer<http.Response>().future;
      });
      Object? outcome;
      geo
          .forward('z')
          .then(
            (v) {
              outcome = v;
            },
            onError: (Object e) {
              outcome = e;
            },
          );
      async.elapse(const Duration(seconds: 26));
      expect(outcome, isA<TimeoutException>());
      expect(calls, 1);
      async.elapse(const Duration(seconds: 40));
    });
  });

  test('isTransientFault: server faults and no network, never 4xx', () {
    expect(
      AppGeocoding.isTransientFault(
        const ApiError(code: 'x', message: '', statusCode: 503),
      ),
      isTrue,
    );
    expect(
      AppGeocoding.isTransientFault(
        const ApiError(code: 'x', message: '', statusCode: 429),
      ),
      isTrue,
    );
    expect(
      AppGeocoding.isTransientFault(
        const ApiError(code: 'NETWORK', message: ''),
      ),
      isTrue,
    );
    expect(
      AppGeocoding.isTransientFault(http.ClientException('reset')),
      isTrue,
    );
    expect(
      AppGeocoding.isTransientFault(
        const ApiError(code: 'TIMEOUT', message: ''),
      ),
      isFalse,
    );
    expect(
      AppGeocoding.isTransientFault(
        const ApiError(code: 'x', message: '', statusCode: 404),
      ),
      isFalse,
    );
    expect(AppGeocoding.isTransientFault(StateError('x')), isFalse);
  });
}
