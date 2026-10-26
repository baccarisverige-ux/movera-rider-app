import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/realtime/api_ride_realtime.dart';
import 'package:movera_rider/core/realtime/realtime_gate.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/driver_arriving/application/driver_tracking_controller.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';

/// Q13 / X19: an admin reassign is not a "driver cancelled". X14: an
/// event kind the app does not know never breaks the feed.
void main() {
  final t0 = DateTime.utc(2026, 10, 20, 9);

  Map<String, Object?> projection(
    String status,
    int version, {
    String? eventKind,
    Map<String, Object?>? cancellation,
  }) => {
    'tripId': 'trip-1',
    'status': status,
    'version': version,
    'updatedAt': t0.add(Duration(seconds: version)).toIso8601String(),
    'eventKind': ?eventKind,
    'cancellation': ?cancellation,
  };

  ApiRideRealtime build(List<Map<String, Object?>> script) {
    var index = 0;
    final rt = ApiRideRealtime(
      api: ApiClient(
        client: MockClient((_) async {
          final next =
              script[index < script.length ? index : script.length - 1];
          index++;
          return http.Response(jsonEncode(next), 200);
        }),
        env: AppEnv.current,
      ),
      pollInterval: const Duration(days: 1),
    );
    addTearDown(rt.dispose);
    return rt;
  }

  Future<List<RideRealtimeEvent>> run(List<Map<String, Object?>> script) async {
    final rt = build(script);
    final events = <RideRealtimeEvent>[];
    final sub = rt.subscribe('trip-1').listen(events.add);
    addTearDown(sub.cancel);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    for (var i = 1; i < script.length; i++) {
      await rt.reconnectAndResync('trip-1');
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    return events;
  }

  test(
    'an admin reassign goes back to searching without a driver cancel',
    () async {
      final events = await run([
        projection('accepted', 1),
        projection('searching', 2, eventKind: 'trip_projection'),
      ]);
      final back = events.last;
      expect(back.isAdminReassign, isTrue);
      expect(back.kind, RealtimeKind.tripProjection);
      expect(back.kind, isNot(RealtimeKind.driverCancelled));
    },
  );

  test('cancellation.actor admin also marks the reassign', () async {
    final events = await run([
      projection('accepted', 1),
      projection('searching', 2, cancellation: {'actor': 'admin'}),
    ]);
    expect(events.last.isAdminReassign, isTrue);
  });

  test('a driver drop is still the driver-cancelled notice', () async {
    final events = await run([
      projection('accepted', 1),
      projection('searching', 2, eventKind: 'driver_cancelled'),
    ]);
    final back = events.last;
    expect(back.isAdminReassign, isFalse);
    expect(back.kind, RealtimeKind.driverCancelled);
    expect(back.status, RideStatus.cancelledByDriver);
  });

  test('the tracking controller remembers it was an admin reassign', () async {
    final rt = build([
      projection('accepted', 1),
      projection('searching', 2, eventKind: 'trip_projection'),
    ]);
    final tracking = DriverTrackingController(
      realtime: rt,
      pickupLat: 59.33,
      pickupLng: 18.06,
      persistRideSnapshot: false,
    );
    addTearDown(tracking.dispose);
    tracking.start(rideId: 'trip-1');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(tracking.reassignedByAdmin, isFalse);
    await rt.reconnectAndResync('trip-1');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(tracking.status, RideStatus.cancelledByDriver);
    expect(tracking.reassignedByAdmin, isTrue);
  });

  test('X14: an unknown event kind does not break the feed', () async {
    final events = await run([
      projection('accepted', 1, eventKind: 'something_new'),
      projection('driver_to_pickup', 2, eventKind: 'another_new_kind'),
    ]);
    expect(events.map((e) => e.status), [
      RideStatus.driverAssigned,
      RideStatus.driverArriving,
    ]);
    expect(events.map((e) => e.kind).toSet(), {RealtimeKind.tripProjection});
    expect(RealtimeKindWire.parse('something_new'), isNull);
  });
}
