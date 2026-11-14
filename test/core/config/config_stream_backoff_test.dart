import 'dart:convert';
import 'dart:math' as math;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/auth/token_store.dart';
import 'package:movera_rider/core/config/api_rider_config_repository.dart';

/// Owner 2026-11-10 (step 62 request budgets): a refused
/// `/rider/config/stream` reconnects after 5 → 10 → 20 → 40 → 60 s (jitter
/// ±10 %), and starts again at 5 s after a successful connect.
///
/// R3 (owner 2026-11-13 12:23 UTC "Yes, update rule (Rec.)", contract
/// v0.18.83 `realtime.connectedRule`, it replaces the 2026-11-10 reading of
/// "a successful connect"): a connect is successful (connected) only once
/// the stream delivered an event or stayed up 30 s; a 200 that closes at
/// once keeps backing off (test/core/config/config_stream_connected_test).
/// So the "reset" step below uses a 200 that delivers an event.
void main() {
  test('settings stream backoff, reset on success (fake clock)', () {
    fakeAsync((async) {
      final opens = <Duration>[];
      var refuse = true;
      final client = MockClient.streaming((request, _) async {
        if (request.url.path.endsWith('/stream')) {
          opens.add(async.elapsed);
          return refuse
              ? http.StreamedResponse(Stream.value(utf8.encode('{}')), 503)
              // R3: a connected stream (it delivered an event) that then
              // closes; before R3 this was an empty 200.
              : http.StreamedResponse(
                  Stream.value(
                    utf8.encode(
                      'event: config_published\ndata: {"kind":"noop"}\n\n',
                    ),
                  ),
                  200,
                );
        }
        return http.StreamedResponse(Stream.value(utf8.encode('{}')), 200);
      });
      final repo = ApiRiderConfigRepository(
        api: ApiClient(
          env: const AppEnv(
            flavor: AppFlavor.staging,
            apiBaseUrl: 'https://api.movera.invalid',
          ),
          client: client,
          tokens: MemoryTokenStore()..save(access: 'a', refresh: 'r'),
        ),
        cache: MemoryRiderConfigCache(),
        random: math.Random(7),
      );
      repo.watch('Z001');
      async.elapse(const Duration(minutes: 4));
      final gaps = [
        for (var i = 1; i < opens.length; i++)
          (opens[i] - opens[i - 1]).inMilliseconds / 1000,
      ];
      const expected = [5, 10, 20, 40, 60, 60];
      for (var i = 0; i < expected.length; i++) {
        expect(gaps[i], greaterThanOrEqualTo(expected[i] * 0.9));
        expect(gaps[i], lessThanOrEqualTo(expected[i] * 1.1));
        expect(gaps[i], inInclusiveRange(5, 60));
      }
      refuse = false;
      async.elapse(const Duration(seconds: 61));
      final reset = opens.length;
      async.elapse(const Duration(seconds: 6));
      expect(opens.length, greaterThan(reset), reason: 'next wait is 5 s');
      repo.dispose();
    });
  });
}
