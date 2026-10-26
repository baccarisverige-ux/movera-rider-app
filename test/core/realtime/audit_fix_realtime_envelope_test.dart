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

/// ARCH-13: the polling transport reads the C-6 event envelope (eventId,
/// version, serverTime, etaSeconds), dedupes by eventId, orders by version,
/// backs off after failures and pauses (never invents a status) when the
/// server no longer knows a ride.
void main() {
  final t0 = DateTime.utc(2026, 10, 14, 9);

  Map<String, Object?> body({
    String status = 'driverArriving',
    int version = 1,
    String? eventId,
    double lat = 59.33,
    DateTime? serverTime,
    DateTime? locationAt,
    int? etaSeconds,
  }) => {
    'code': 'OK',
    if (eventId != null) 'eventId': eventId,
    if (serverTime != null) 'serverTime': serverTime.toIso8601String(),
    'ride': {
      'id': 'ride-1',
      'status': status,
      'version': version,
      'updatedAt': t0.toIso8601String(),
      'driverLat': lat,
      'driverLng': 18.06,
      if (locationAt != null) 'locationAt': locationAt.toIso8601String(),
      if (etaSeconds != null) 'etaSeconds': etaSeconds,
    },
  };

  ({ApiRideRealtime rt, List<int> calls}) build(
    List<Object> script, {
    DateTime Function()? clock,
    RealtimeConnection? connection,
  }) {
    final calls = <int>[];
    var index = 0;
    final rt = ApiRideRealtime(
      api: ApiClient(
        client: MockClient((_) async {
          calls.add(index);
          final next =
              script[index < script.length ? index : script.length - 1];
          index++;
          if (next is int) return http.Response('{"code":"NOT_FOUND"}', next);
          return http.Response(jsonEncode(next), 200);
        }),
        env: AppEnv.current,
      ),
      connection: connection,
      pollInterval: const Duration(days: 1),
      clock: clock,
    );
    addTearDown(rt.dispose);
    return (rt: rt, calls: calls);
  }

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 20));

  test(
    'a replayed eventId is delivered once, even with a changed location',
    () async {
      final t = build([
        body(eventId: 'ev-1', lat: 59.33),
        body(eventId: 'ev-1', lat: 59.34),
        body(eventId: 'ev-2', version: 2, lat: 59.35),
      ]);
      final events = <RideRealtimeEvent>[];
      final sub = t.rt.subscribe('ride-1').listen(events.add);
      await settle();
      await t.rt.reconnectAndResync('ride-1');
      await t.rt.reconnectAndResync('ride-1');
      await settle();
      expect(events.map((e) => e.eventId), ['ev-1', 'ev-2']);
      expect(events.map((e) => e.version), [1, 2]);
      await sub.cancel();
    },
  );

  test('an older server version never follows a newer one', () async {
    final t = build([
      body(eventId: 'ev-3', version: 3, status: 'driverWaiting'),
      body(eventId: 'ev-2', version: 2, status: 'driverArriving'),
    ]);
    final events = <RideRealtimeEvent>[];
    final sub = t.rt.subscribe('ride-1').listen(events.add);
    await settle();
    await t.rt.reconnectAndResync('ride-1');
    await settle();
    expect(events.map((e) => e.status), [RideStatus.driverWaiting]);
    await sub.cancel();
  });

  test(
    'server ETA is passed on and location age uses the server clock',
    () async {
      final device = t0.add(
        const Duration(minutes: 3),
      ); // device clock 3 min fast
      final t = build([
        body(
          eventId: 'ev-1',
          serverTime: t0.add(const Duration(seconds: 5)),
          locationAt: t0,
          etaSeconds: 240,
        ),
      ], clock: () => device);
      final events = <RideRealtimeEvent>[];
      final sub = t.rt.subscribe('ride-1').listen(events.add);
      await settle();
      final event = events.single;
      expect(event.etaSeconds, 240);
      // Five seconds old on the server is five seconds old on this device,
      // whatever the device clock says.
      expect(event.locationAt, device.subtract(const Duration(seconds: 5)));
      expect(event.payload['serverLocationAt'], t0.toIso8601String());
      await sub.cancel();
    },
  );

  test('rider-r4-9: a bare projection (no serverTime) ages the fix by its own '
      'updatedAt, not by the device clock', () async {
    final device = t0.add(const Duration(minutes: 3));
    final t = build([
      {
        'id': 'ride-1',
        'status': 'driverArriving',
        'version': 1,
        'updatedAt': t0.add(const Duration(seconds: 5)).toIso8601String(),
        'driverLocation': {
          'lat': 59.33,
          'lng': 18.06,
          'measuredAt': t0.toIso8601String(),
        },
      },
    ], clock: () => device);
    final event = await t.rt.subscribe('ride-1').first;
    expect(event.locationAt, device.subtract(const Duration(seconds: 5)));
  });

  test(
    'the transport sequence does not restart when a screen re-subscribes',
    () async {
      final t = build([
        body(eventId: 'ev-1'),
        body(eventId: 'ev-2', version: 2),
      ]);
      final first = <RideRealtimeEvent>[];
      final a = t.rt.subscribe('ride-1').listen(first.add);
      await settle();
      await a.cancel();
      final second = <RideRealtimeEvent>[];
      final b = t.rt.subscribe('ride-1').listen(second.add);
      await settle();
      expect(first.single.sequence, 1);
      expect(second.single.sequence, 2);
      await b.cancel();
    },
  );

  test('after a failure the next tick waits for the backoff', () async {
    var now = t0;
    final t = build([500, body(eventId: 'ev-1')], clock: () => now);
    final events = <RideRealtimeEvent>[];
    final sub = t.rt.subscribe('ride-1').listen(events.add);
    await settle();
    final afterFailure = t.calls.length;
    // A plain tick inside the backoff window does not call the server.
    t.rt.researchAfterDriverCancel();
    await settle();
    expect(t.calls.length, afterFailure);
    now = t0.add(const Duration(seconds: 5));
    t.rt.researchAfterDriverCancel();
    await settle();
    expect(t.calls.length, greaterThan(afterFailure));
    expect(events, hasLength(1));
    await sub.cancel();
  });

  test(
    'repeated 404 pauses polling without inventing a status (contract v0.3.0)',
    () async {
      var now = t0;
      final connection = RealtimeConnection();
      final t = build(
        [body(eventId: 'ev-1', version: 4), 404],
        clock: () => now,
        connection: connection,
      );
      final events = <RideRealtimeEvent>[];
      final sub = t.rt.subscribe('ride-1').listen(events.add);
      await settle();
      for (var i = 0; i < 3; i++) {
        await t.rt.reconnectAndResync('ride-1');
      }
      await settle();
      // No client-made cancelledBySystem: the last server status stands and
      // the connection shows a problem.
      expect(events, hasLength(1));
      expect(events.single.status, RideStatus.driverArriving);
      expect(connection.state, RealtimeState.failed);
      final calls = t.calls.length;
      now = t0.add(const Duration(hours: 1));
      t.rt.researchAfterDriverCancel();
      await settle();
      expect(t.calls.length, calls, reason: 'polling is paused');
      // An explicit resync asks the server once more.
      await t.rt.reconnectAndResync('ride-1');
      await settle();
      expect(t.calls.length, calls + 1);
      await sub.cancel();
    },
  );
}
