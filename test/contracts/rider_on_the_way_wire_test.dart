import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/auth/token_store.dart';
import 'package:movera_rider/core/realtime/api_ride_realtime.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';

/// Contract v0.5.4: on the live wire the rider's "I'm on the way" is
/// `POST /trips/{tripId}/on-the-way`, which the driver hears as a
/// `rider_on_the_way` event. The demo's polling transport has no signals.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const staging = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://api.movera.test',
  );
  const demo = AppEnv(
    flavor: AppFlavor.test,
    apiBaseUrl: 'https://api.test.movera.invalid',
  );

  test('live: the signal posts to /trips/{id}/on-the-way with a bearer and '
      'an Idempotency-Key, no body fields', () async {
    final requests = <http.Request>[];
    final tokens = MemoryTokenStore();
    await tokens.save(access: 'a1', refresh: 'r1');
    final api = ApiClient(
      env: staging,
      tokens: tokens,
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode({'tripId': 'trp_1', 'status': 'arrived', 'version': 5}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final realtime = ApiRideRealtime(api: api);
    expect(realtime.supportsRiderSignals, isTrue);

    await realtime.sendSignal(
      rideId: 'trp_1',
      signal: RideRealtimeSignal.riderOnTheWay,
    );

    final sent = requests.single;
    expect(sent.method, 'POST');
    expect(sent.url.path, '/api/v1/trips/trp_1/on-the-way');
    expect(sent.headers['Authorization'], 'Bearer a1');
    expect(sent.headers['Idempotency-Key'], isNotEmpty);
    expect(jsonDecode(sent.body), <String, dynamic>{});
    realtime.dispose();
  });

  test('the polling transport of the demo has no rider signals', () async {
    final api = ApiClient(
      env: demo,
      tokens: MemoryTokenStore(),
      client: MockClient((_) async => http.Response('{}', 200)),
    );
    final realtime = ApiRideRealtime(api: api);
    expect(realtime.supportsRiderSignals, isFalse);
    await expectLater(
      realtime.sendSignal(
        rideId: 'trp_1',
        signal: RideRealtimeSignal.riderOnTheWay,
      ),
      throwsUnsupportedError,
    );
    realtime.dispose();
  });
}
