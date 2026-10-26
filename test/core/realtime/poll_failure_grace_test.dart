import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/realtime/api_ride_realtime.dart';
import 'package:movera_rider/core/realtime/realtime_connection.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';

/// Live stability: the search polls GET /rides/{id} every 2 s. On the live
/// server (slow, sleeps when idle, the odd 503) the poll fails now and then
/// for a while. The trip lives on the server: the poll rides it out, says
/// "Reconnecting" first, "Connection problem" after a run of failures, and
/// is back within seconds of the server, never ending the search itself.
void main() {
  const live = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://x.invalid',
  );
  final t0 = DateTime.utc(2026, 10, 26, 9);
  String searching(int version) => jsonEncode({
    'tripId': 'trp_1',
    'status': 'searching',
    'version': version,
    'updatedAt': t0.add(Duration(seconds: version)).toIso8601String(),
  });

  test('minutes of failures keep the search; recovery is quick', () {
    fakeAsync((async) {
      var now = t0;
      var calls = 0;
      var down = false;
      final connection = RealtimeConnection();
      final rt = ApiRideRealtime(
        api: ApiClient(
          client: MockClient((_) async {
            calls++;
            if (down) throw http.ClientException('connection refused');
            return http.Response(searching(calls), 200);
          }),
          env: live,
        ),
        connection: connection,
        clock: () => now,
        pollInterval: const Duration(seconds: 2),
      );
      final events = <RideRealtimeEvent>[];
      var done = false;
      final sub = rt
          .subscribe('trp_1')
          .listen(events.add, onDone: () => done = true);
      async.flushMicrotasks();
      expect(connection.state, RealtimeState.connected);
      expect(events.single.status, RideStatus.findingDriver);

      down = true;
      final before = calls;
      // Three minutes of a server that refuses every connection.
      for (var s = 0; s < 180; s += 2) {
        now = now.add(const Duration(seconds: 2));
        async.elapse(const Duration(seconds: 2));
      }
      expect(done, isFalse, reason: 'the stream stays open');
      expect(events, hasLength(1), reason: 'no status was made up');
      expect(connection.state, RealtimeState.failed);
      final attempts = calls - before;
      // Backed off: a few polls a minute, not one every 2 s, but never stopped.
      expect(attempts, inInclusiveRange(12, 40), reason: '$attempts attempts');

      down = false;
      final recoveredAt = calls;
      for (var s = 0; s < 10; s += 2) {
        now = now.add(const Duration(seconds: 2));
        async.elapse(const Duration(seconds: 2));
        if (connection.state == RealtimeState.connected) break;
      }
      expect(
        connection.state,
        RealtimeState.connected,
        reason: 'back within 10 s',
      );
      expect(calls, greaterThan(recoveredAt));
      expect(events.last.status, RideStatus.findingDriver);

      sub.cancel();
      rt.dispose();
      connection.dispose();
      async.flushMicrotasks();
      expect(async.pendingTimers, isEmpty, reason: 'nothing left running');
    });
  });

  test('reconnecting for the first misses, failed after three', () {
    fakeAsync((async) {
      var now = t0;
      var fail = true;
      final connection = RealtimeConnection();
      final rt = ApiRideRealtime(
        api: ApiClient(
          client: MockClient(
            (_) async => fail
                ? http.Response('{"code":"unavailable"}', 503)
                : http.Response(searching(1), 200),
          ),
          env: live,
        ),
        connection: connection,
        clock: () => now,
        pollInterval: const Duration(seconds: 2),
      );
      final sub = rt.subscribe('trp_1').listen((_) {});
      async.flushMicrotasks();
      expect(connection.state, RealtimeState.reconnecting);
      now = now.add(const Duration(seconds: 2));
      async.elapse(const Duration(seconds: 2));
      expect(connection.state, RealtimeState.reconnecting);
      now = now.add(const Duration(seconds: 4));
      async.elapse(const Duration(seconds: 4));
      expect(connection.state, RealtimeState.failed);
      fail = false;
      now = now.add(const Duration(seconds: 8));
      async.elapse(const Duration(seconds: 8));
      expect(connection.state, RealtimeState.connected);

      sub.cancel();
      rt.dispose();
      connection.dispose();
      async.flushMicrotasks();
      expect(async.pendingTimers, isEmpty, reason: 'nothing left running');
    });
  });
}
