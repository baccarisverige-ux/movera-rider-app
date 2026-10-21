import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/realtime/api_ride_realtime.dart';
import 'package:movera_rider/core/realtime/realtime_connection.dart';
import 'package:movera_rider/core/realtime/realtime_gate.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/driver_arriving/application/driver_tracking_controller.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';

/// Wave 4 R4.10: the polling transport and the demo driver.
void main() {
  final t0 = DateTime.utc(2026, 10, 21, 9);

  Map<String, Object?> projection(
    String status,
    int version, {
    String? driverId,
  }) => {
    'tripId': 'trip-1',
    'status': status,
    'version': version,
    'updatedAt': t0.add(Duration(seconds: version)).toIso8601String(),
    if (driverId != null)
      'driver': {'driverId': driverId, 'firstName': driverId, 'vehicle': {}},
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

  /// Answers [script] in order, then keeps repeating its last projection.
  ApiRideRealtime scripted(List<Map<String, Object?>> script) {
    var index = 0;
    return polling(() => http.Response(
      jsonEncode(script[index < script.length ? index++ : script.length - 1]),
      200,
    ));
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

  group('rider-u23 a driver drop the polls skipped over', () {
    testWidgets('a new subscription after the handover still sees it',
        (tester) async {
      final rt = scripted([
        projection('accepted', 2, driverId: 'elin'),
        projection('searching', 3),
      ]);
      // Finding saw the accept, then handed over to Waiting.
      final finding = rt.subscribe('trip-1').listen((_) {});
      await tester.pump();
      unawaited(finding.cancel());
      final events = <RideRealtimeEvent>[];
      rt.subscribe('trip-1').listen(events.add);
      await tester.pump();

      expect(events.single.status, RideStatus.cancelledByDriver);
      expect(events.single.kind, RealtimeKind.driverCancelled);
      rt.dispose();
    });

    testWidgets('another driver accepting before the next poll is a drop',
        (tester) async {
      final rt = scripted([
        projection('driver_to_pickup', 2, driverId: 'elin'),
        projection('accepted', 5, driverId: 'omar'),
      ]);
      final events = <RideRealtimeEvent>[];
      rt.subscribe('trip-1').listen(events.add);
      while (events.isEmpty) {
        await tester.pump();
      }
      await rt.reconnectAndResync('trip-1');
      await tester.pump();

      expect(events.last.status, RideStatus.driverAssigned);
      expect(events.last.driver?.id, 'omar');
      expect(events.last.kind, RealtimeKind.driverCancelled);
      rt.dispose();
    });

    testWidgets('Waiting is told which driver it lost', (tester) async {
      final rt = scripted([
        projection('arrived', 2, driverId: 'elin'),
        projection('accepted', 5, driverId: 'omar'),
      ]);
      final tracking = DriverTrackingController(
        realtime: rt,
        pickupLat: 59.33,
        pickupLng: 18.06,
        persistRideSnapshot: false,
      )..start(rideId: 'trip-1');
      while (tracking.driver == null) {
        await tester.pump();
      }
      expect(tracking.takeReplacedDriver(), isNull);
      await rt.reconnectAndResync('trip-1');
      await tester.pump();

      expect(tracking.takeReplacedDriver()?.id, 'elin');
      expect(tracking.driver?.id, 'omar');
      expect(tracking.waitingSince, isNull, reason: 'a new wait to come');
      tracking.dispose();
      rt.dispose();
    });
  });
}
