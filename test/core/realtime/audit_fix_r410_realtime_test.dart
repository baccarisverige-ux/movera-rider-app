import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/contracts/matched_driver.dart';
import 'package:movera_rider/core/maps/geo_distance.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
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
    return polling(
      () => http.Response(
        jsonEncode(script[index < script.length ? index++ : script.length - 1]),
        200,
      ),
    );
  }

  testWidgets('rider-23: a resync after the not-found pause polls again', (
    tester,
  ) async {
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
    testWidgets('a new subscription after the handover still sees it', (
      tester,
    ) async {
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

    testWidgets('another driver accepting before the next poll is a drop', (
      tester,
    ) async {
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

  group('demo driver (MockRideRealtime) uses the trip\'s own pickup', () {
    const paris = (lat: 48.8809, lng: 2.3553);
    const arlanda = (lat: 59.6519, lng: 17.9186);
    const sara = MatchedDriver(id: 'd-sara', firstName: 'Sara');
    late InProcessMockClient server;
    late MockRideRealtime mock;
    late List<RideRealtimeEvent> events;

    setUp(() {
      server = InProcessMockClient();
      mock = MockRideRealtime(api: ApiClient(client: server));
      events = [];
    });

    void seed(
      String id,
      String status,
      ({double lat, double lng}) at, [
      Map<String, Object?> extra = const {},
    ]) {
      server.rides[id] = {
        'id': id,
        'tripId': id,
        'status': status,
        'version': 3,
        'pickupLat': at.lat,
        'pickupLng': at.lng,
        ...extra,
      };
    }

    double metresFrom(({double lat, double lng}) at, RideRealtimeEvent e) =>
        GeoDistance.metersBetween(e.latitude!, e.longitude!, at.lat, at.lng);

    Future<RideRealtimeEvent> next(
      WidgetTester tester,
      RideStatus status,
    ) async {
      for (var i = 0; i < 200; i++) {
        final hit = events.where((e) => e.status == status);
        if (hit.isNotEmpty) return hit.last;
        await tester.pump(const Duration(milliseconds: 100));
      }
      fail('no $status event');
    }

    Future<RideRealtimeEvent> assign(WidgetTester tester, String id) async {
      events.clear();
      mock.subscribe(id).listen(events.add);
      mock.assignNow();
      return next(tester, RideStatus.driverAssigned);
    }

    testWidgets('rider-24: the first driver spawns near the booked pickup', (
      tester,
    ) async {
      seed('r-paris', 'searching', paris);
      final assigned = await assign(tester, 'r-paris');
      expect(metresFrom(paris, assigned), lessThan(2000));
      mock.dispose();
    });

    testWidgets('rider-24: a reload resumes at the pickup, on server clocks', (
      tester,
    ) async {
      seed('r-paris', 'driver_to_pickup', paris, {
        'acceptedAt': '2026-10-21T08:58:00Z',
      });
      mock.primeResume(status: RideStatus.driverArriving, driver: sara);
      mock.subscribe('r-paris').listen(events.add);
      final resumed = await next(tester, RideStatus.driverArriving);
      expect(metresFrom(paris, resumed), lessThan(2000));
      expect(resumed.acceptedAt, DateTime.utc(2026, 10, 21, 8, 58));
      mock.dispose();
    });

    testWidgets('rider-u27: a reload while the driver waits stays waiting', (
      tester,
    ) async {
      seed('r-wait', 'arrived', paris);
      mock.primeResume(status: RideStatus.driverWaiting, driver: sara);
      mock.subscribe('r-wait').listen(events.add);
      final resumed = await next(tester, RideStatus.driverWaiting);
      expect(metresFrom(paris, resumed), lessThan(50));
      await next(tester, RideStatus.tripStarted);
      expect(
        events.map((e) => e.status),
        isNot(contains(RideStatus.driverArriving)),
      );
      mock.dispose();
    });

    testWidgets('rider-u28: the next ride\'s driver spawns at its own pickup', (
      tester,
    ) async {
      seed('r-paris', 'searching', paris);
      seed('r-arlanda', 'searching', arlanda);
      await assign(tester, 'r-paris');
      final second = await assign(tester, 'r-arlanda');
      expect(metresFrom(arlanda, second), lessThan(2000));
      mock.dispose();
    });
  });
}
