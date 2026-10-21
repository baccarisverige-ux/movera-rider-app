import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/realtime/api_ride_realtime.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';

/// Wave 5 R5.2: the polling transport tells the truth about fresh fixes.
void main() {
  testWidgets(
      'rider-u24: a stationary driver\'s newer fix is delivered, not dropped',
      (tester) async {
    final t0 = DateTime.utc(2026, 10, 21, 9);
    var poll = 0;
    // Same version, updatedAt, status and coordinates; only measuredAt moves.
    final rt = ApiRideRealtime(
      api: ApiClient(
        client: MockClient((_) async => http.Response(
              jsonEncode({
                'tripId': 'trip-1',
                'status': 'arrived',
                'version': 4,
                'updatedAt': t0.toIso8601String(),
                'driverLocation': {
                  'lat': 59.33,
                  'lng': 18.06,
                  'measuredAt':
                      t0.add(Duration(seconds: 5 * poll++)).toIso8601String(),
                },
              }),
              200,
            )),
        env: AppEnv.current,
      ),
      pollInterval: const Duration(seconds: 2),
    );
    addTearDown(rt.dispose);
    final events = <RideRealtimeEvent>[];
    final sub = rt.subscribe('trip-1').listen(events.add);
    addTearDown(sub.cancel);
    await tester.pump();
    await rt.reconnectAndResync('trip-1');
    await tester.pump();

    expect(events, hasLength(2), reason: 'the second fix is fresh');
    expect(events.last.locationAt!.isAfter(events.first.locationAt!), isTrue);
    rt.dispose();
  });
}
