import 'dart:async';
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
import 'package:movera_rider/core/realtime/api_ride_realtime.dart';

/// R3 (owner 2026-11-13 12:23 UTC "Yes, update rule (Rec.)"; contract
/// v0.18.83 `realtime.connectedRule`): a stream counts as connected only
/// after it delivered an event or stayed up 30 s; a 200 alone is not
/// connected. Only a connected stream resets the reconnect backoff, so a
/// stream the busy server opens and drops at once keeps backing off
/// (5 → 10 → 20 → 40 → 60 s) and never storms the server. A 429 / 503
/// Retry-After is honoured (at most 60 s).
void main() {
  const env = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://api.movera.invalid',
  );

  ({ApiRiderConfigRepository repo, List<Duration> opens}) build(
    FakeAsync async,
    http.StreamedResponse Function(int open) stream,
  ) {
    final opens = <Duration>[];
    final client = MockClient.streaming((request, _) async {
      if (request.url.path.endsWith('/stream')) {
        opens.add(async.elapsed);
        return stream(opens.length);
      }
      return http.StreamedResponse(Stream.value(utf8.encode('{}')), 200);
    });
    final repo = ApiRiderConfigRepository(
      api: ApiClient(
        env: env,
        client: client,
        tokens: MemoryTokenStore()..save(access: 'a', refresh: 'r'),
      ),
      cache: MemoryRiderConfigCache(),
      random: math.Random(7),
    );
    return (repo: repo, opens: opens);
  }

  List<double> gaps(List<Duration> opens) => [
    for (var i = 1; i < opens.length; i++)
      (opens[i] - opens[i - 1]).inMilliseconds / 1000,
  ];

  void near(double gap, int seconds) {
    expect(gap, greaterThanOrEqualTo(seconds * 0.9));
    expect(gap, lessThanOrEqualTo(seconds * 1.1));
  }

  http.StreamedResponse dropAtOnce() =>
      http.StreamedResponse(const Stream.empty(), 200);

  test('open-then-drop: a 200 the server closes at once is not connected; '
      'the backoff keeps growing (no 5 s storm)', () {
    fakeAsync((async) {
      final r = build(async, (_) => dropAtOnce());
      r.repo.watch('Z001');
      async.elapse(const Duration(minutes: 3));
      final g = gaps(r.opens);
      // Before R3: a reconnect every 5 s for 3 minutes (~36 opens).
      expect(r.opens.length, lessThanOrEqualTo(8));
      const expected = [5, 10, 20, 40, 60];
      for (var i = 0; i < expected.length; i++) {
        near(g[i], expected[i]);
      }
      r.repo.dispose();
    });
  });

  test('an event makes the stream connected: after its close the next '
      'wait is 5 s again', () {
    fakeAsync((async) {
      final r = build(async, (open) {
        // Opens 1-3 drop at once (5, 10, 20 s); open 4 delivers an event.
        if (open != 4) return dropAtOnce();
        return http.StreamedResponse(
          Stream.value(
            utf8.encode('event: config_published\ndata: {"kind":"noop"}\n\n'),
          ),
          200,
        );
      });
      r.repo.watch('Z001');
      async.elapse(const Duration(seconds: 45));
      expect(r.opens.length, 5);
      final g = gaps(r.opens);
      near(g[0], 5);
      near(g[1], 10);
      near(g[2], 20);
      near(g[3], 5);
      r.repo.dispose();
    });
  });

  test('over 30 s up counts as connected (next wait 5 s); 29 s does not', () {
    for (final (upFor, wait) in [(31, 5), (29, 40)]) {
      fakeAsync((async) {
        final r = build(async, (open) {
          if (open != 4) return dropAtOnce();
          // Open 4 stays up with heartbeats only (no event), then closes.
          final body = StreamController<List<int>>();
          Timer(
            const Duration(seconds: 15),
            () => body.add(utf8.encode(': heartbeat\n')),
          );
          Timer(Duration(seconds: upFor), body.close);
          return http.StreamedResponse(body.stream, 200);
        });
        r.repo.watch('Z001');
        async.elapse(
          const Duration(seconds: 35) + Duration(seconds: upFor + wait + 2),
        );
        final g = gaps(r.opens);
        expect(g.length, greaterThanOrEqualTo(4), reason: 'up $upFor s');
        near(g[3] - upFor, wait);
        r.repo.dispose();
      });
    }
  });

  test('a 503 with Retry-After 40 is not asked again sooner; over 60 s waits '
      '60 s', () {
    for (final (header, wait) in [('40', 40), ('300', 60)]) {
      fakeAsync((async) {
        final r = build(
          async,
          (_) => http.StreamedResponse(
            Stream.value(utf8.encode('{"code":"server_busy"}')),
            503,
            headers: {'retry-after': header},
          ),
        );
        r.repo.watch('Z001');
        async.elapse(Duration(seconds: wait - 1));
        expect(r.opens.length, 1, reason: 'Retry-After $header');
        async.elapse(const Duration(seconds: 8));
        expect(r.opens.length, 2, reason: 'Retry-After $header');
        r.repo.dispose();
      });
    }
  });

  test('the trip stream honours Retry-After on a 503 (at most 60 s)', () {
    fakeAsync((async) {
      final opens = <Duration>[];
      final rt = ApiRideRealtime(
        api: ApiClient(
          env: env,
          client: MockClient.streaming((request, _) async {
            if (request.url.path.endsWith('/events')) {
              opens.add(async.elapsed);
              return http.StreamedResponse(
                Stream.value(utf8.encode('{"code":"server_busy"}')),
                503,
                headers: {'retry-after': '40'},
              );
            }
            return http.StreamedResponse(
              Stream.value(
                utf8.encode(
                  jsonEncode({
                    'tripId': 'trp_1',
                    'status': 'driver_to_pickup',
                    'version': 1,
                    'sequence': 1,
                    'updatedAt': '2026-11-13T12:00:00Z',
                  }),
                ),
              ),
              200,
            );
          }),
        ),
      );
      final sub = rt.subscribe('trp_1').listen((_) {});
      async.elapse(const Duration(seconds: 39));
      expect(opens.length, 1, reason: 'not before Retry-After (40 s)');
      async.elapse(const Duration(seconds: 3));
      expect(opens.length, 2);
      unawaited(sub.cancel());
      rt.dispose();
      async.flushMicrotasks();
    });
  });
}
