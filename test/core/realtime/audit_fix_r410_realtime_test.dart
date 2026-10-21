import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/realtime/api_ride_realtime.dart';
import 'package:movera_rider/core/realtime/realtime_connection.dart';

/// Wave 4 R4.10: the polling transport and the demo driver.
void main() {
  final t0 = DateTime.utc(2026, 10, 21, 9);

  Map<String, Object?> projection(String status, int version) => {
    'tripId': 'trip-1',
    'status': status,
    'version': version,
    'updatedAt': t0.add(Duration(seconds: version)).toIso8601String(),
  };

  /// Polls every 2 s; [answer] is the server's reply to each GET.
  ApiRideRealtime polling(http.Response Function() answer) {
    final rt = ApiRideRealtime(
      api: ApiClient(
        client: MockClient((_) async => answer()),
        env: AppEnv.current,
      ),
      pollInterval: const Duration(seconds: 2),
    );
    addTearDown(rt.dispose);
    return rt;
  }

  testWidgets('rider-23: a resync after the not-found pause polls again',
      (tester) async {
    var calls = 0;
    var gone = true;
    final rt = polling(() {
      calls++;
      return gone
          ? http.Response(jsonEncode({'code': 'not_found'}), 404)
          : http.Response(jsonEncode(projection('accepted', calls)), 200);
    });
    final sub = rt.subscribe('trip-1').listen((_) {});
    addTearDown(sub.cancel);
    await tester.pump();
    await rt.reconnectAndResync('trip-1');
    await rt.reconnectAndResync('trip-1');
    expect(calls, 3);
    expect(rt.connection.state, RealtimeState.failed, reason: 'paused');

    gone = false;
    await rt.reconnectAndResync('trip-1');
    expect(rt.connection.state, RealtimeState.connected);
    final resynced = calls;
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    expect(calls, resynced + 2, reason: 'periodic polling is back');
    rt.dispose(); // Its timers end with the test.
  });
}
