import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/realtime/api_ride_realtime.dart';
import 'package:movera_rider/core/realtime/realtime_connection.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';

void main() {
  final t1 = DateTime.utc(2026, 9, 27, 10);
  final t2 = t1.add(const Duration(seconds: 1));

  Map<String, Object?> projection(String status, int version, DateTime at) =>
      {'ride': {
        'status': status,
        'version': version,
        'updatedAt': at.toIso8601String(),
      }};

  ApiRideRealtime transport(
    Future<http.Response> Function(http.Request) handle, {
    RealtimeConnection? connection,
  }) => ApiRideRealtime(
    api: ApiClient(client: MockClient(handle), env: AppEnv.current),
    connection: connection,
    pollInterval: const Duration(days: 1),
  );

  test('two subscribers share the ride, cancelling one keeps the other live',
      () async {
    var calls = 0;
    final rt = transport((_) async =>
        http.Response(jsonEncode(projection('driverAssigned', ++calls, t1)), 200));
    addTearDown(rt.dispose);
    final first = <RideRealtimeEvent>[];
    final second = <RideRealtimeEvent>[];
    final a = rt.subscribe('ride-123').listen(first.add);
    final b = rt.subscribe('ride-123').listen(second.add);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(calls, 1);
    expect(first.length, 1);
    expect(second.length, 1);
    await a.cancel();
    rt.unsubscribe(); // Finding's legacy cleanup must not close Waiting.
    await rt.reconnectAndResync('ride-123');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(second.length, 2);
    await b.cancel();
  });

  test('unknown status preserves last good status and reports degraded', () async {
    var calls = 0;
    final connection = RealtimeConnection();
    addTearDown(connection.dispose);
    final rt = transport((_) async => http.Response(jsonEncode(
      ++calls == 1
          ? projection('driverAssigned', 1, t1)
          : projection('newServerState', 2, t2),
    ), 200), connection: connection);
    addTearDown(rt.dispose);
    final events = <RideRealtimeEvent>[];
    final sub = rt.subscribe('ride-123').listen(events.add);
    addTearDown(sub.cancel);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(events.single.status, RideStatus.driverAssigned);
    await rt.reconnectAndResync('ride-123');
    expect(events.length, 1);
    expect(connection.state, RealtimeState.failed);
  });

  test('poll never overlaps; backend version and time reject stale projection',
      () async {
    var calls = 0;
    final pending = Completer<http.Response>();
    final rt = transport((_) async {
      calls++;
      if (calls == 1) return pending.future;
      return http.Response(jsonEncode(projection('findingDriver', 1, t1)), 200);
    });
    addTearDown(rt.dispose);
    final events = <RideRealtimeEvent>[];
    final sub = rt.subscribe('ride-123').listen(events.add);
    addTearDown(sub.cancel);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await rt.reconnectAndResync('ride-123');
    expect(calls, 1);
    pending.complete(http.Response(
      jsonEncode(projection('driverAssigned', 2, t2)), 200));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await rt.reconnectAndResync('ride-123');
    expect(events.map((e) => e.status), [RideStatus.driverAssigned]);
    expect(events.single.version, 2);
    expect(events.single.serverTime, t2);
  });

  test('failed poll shows reconnecting first, failed after a run, and '
      'recovery clears it', () async {
    var calls = 0;
    var down = true;
    final connection = RealtimeConnection();
    addTearDown(connection.dispose);
    final rt = transport((_) async {
      calls++;
      return down
          ? http.Response('error', 503)
          : http.Response(jsonEncode(projection('findingDriver', 1, t1)), 200);
    }, connection: connection);
    addTearDown(rt.dispose);
    final sub = rt.subscribe('ride-123').listen((_) {});
    addTearDown(sub.cancel);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    // Live stability: one refused answer from a slow server is a blip.
    expect(connection.state, RealtimeState.reconnecting);
    await rt.reconnectAndResync('ride-123');
    expect(connection.state, RealtimeState.reconnecting);
    await rt.reconnectAndResync('ride-123');
    expect(connection.state, RealtimeState.failed, reason: 'third in a row');
    expect(calls, 3);
    down = false;
    await rt.reconnectAndResync('ride-123');
    expect(connection.state, RealtimeState.connected);
  });

  test('placeholder and missing ride IDs never request an endpoint', () {
    var requests = 0;
    final rt = transport((_) async {
      requests++;
      return http.Response('{}', 200);
    });
    addTearDown(rt.dispose);
    expect(() => rt.subscribe('ride'), throwsStateError);
    expect(() => rt.subscribe('  '), throwsStateError);
    expect(requests, 0);
  });
}
