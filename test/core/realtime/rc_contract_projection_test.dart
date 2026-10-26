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
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';

import '../../contracts/contract_fixtures.dart';

/// RC-01, RC-05, RC-06, X6: the polling transport reads contract-shaped
/// trip projections. A projection's `kind` is the TripKind and its
/// `sequence` a resync cursor (minimum 0); a success answer is the bare
/// projection, the `{code, ride}` envelope is still read during migration.
void main() {
  Map<String, Object?> projection({
    required String status,
    required int version,
    required int sequence,
    String? paymentStatus,
    String? ratingStatus,
    Map<String, Object?>? driverLocation,
  }) => {
    'tripId': 'ride-1',
    'status': status,
    'kind': 'live',
    'version': version,
    'sequence': sequence,
    'updatedAt': DateTime.utc(2026, 10, 19, 9, 0, version).toIso8601String(),
    if (paymentStatus != null) 'paymentStatus': paymentStatus,
    if (ratingStatus != null) 'ratingStatus': ratingStatus,
    if (driverLocation != null) 'driverLocation': driverLocation,
  };

  Map<String, Object?> wrapped(Map<String, Object?> ride) => {
    'code': 'OK',
    'ride': {...ride, 'id': ride['tripId']},
  };

  ({ApiRideRealtime rt, List<http.Request> requests, RealtimeConnection conn})
  build(List<Map<String, Object?>> script) {
    var i = 0;
    final requests = <http.Request>[];
    final conn = RealtimeConnection();
    final rt = ApiRideRealtime(
      api: ApiClient(
        client: MockClient((request) async {
          requests.add(request);
          final next = script[i < script.length ? i : script.length - 1];
          i++;
          return http.Response(jsonEncode(next), 200);
        }),
        env: AppEnv.current,
      ),
      connection: conn,
      pollInterval: const Duration(days: 1),
    );
    addTearDown(rt.dispose);
    return (rt: rt, requests: requests, conn: conn);
  }

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 20));

  Future<List<RideRealtimeEvent>> run(List<Map<String, Object?>> script) async {
    final t = build(script);
    final seen = <RideRealtimeEvent>[];
    final sub = t.rt.subscribe('ride-1').listen(seen.add);
    addTearDown(sub.cancel);
    await settle();
    for (var i = 1; i < script.length; i++) {
      await t.rt.reconnectAndResync('ride-1');
      await settle();
    }
    return seen;
  }

  final paymentProgress = [
    projection(
      status: 'completed',
      version: 7,
      sequence: 7,
      paymentStatus: 'authorized',
      ratingStatus: 'not_requested',
    ),
    projection(
      status: 'completed',
      version: 8,
      sequence: 8,
      paymentStatus: 'captured',
      ratingStatus: 'pending',
    ),
    projection(
      status: 'completed',
      version: 9,
      sequence: 9,
      paymentStatus: 'captured',
      ratingStatus: 'submitted',
    ),
  ];

  test('RC-01: payment and rating progress after `completed` reaches the '
      'rider (enveloped contract projections)', () async {
    final seen = await run(paymentProgress.map(wrapped).toList());
    expect(seen.map((e) => e.status), [
      RideStatus.paymentProcessing,
      RideStatus.ratingPending,
      RideStatus.closed,
    ]);
    expect(seen.map((e) => e.kind).skip(1), [
      RealtimeKind.paymentUpdated,
      RealtimeKind.ratingUpdated,
    ]);
  });

  test('RC-01 / X6: the same progress as bare projections', () async {
    final seen = await run(paymentProgress);
    expect(seen.map((e) => e.status), [
      RideStatus.paymentProcessing,
      RideStatus.ratingPending,
      RideStatus.closed,
    ]);
  });

  test('a lifecycle change after a terminal status is still blocked', () async {
    final seen = await run([
      projection(status: 'cancelled_by_admin', version: 6, sequence: 6),
      projection(status: 'completed', version: 7, sequence: 7),
    ]);
    expect(seen.map((e) => e.status), [RideStatus.cancelledByAdmin]);
  });

  test('RC-05: a projection at sequence 0 (no event yet) is delivered and '
      'ordered by version', () async {
    final seen = await run([
      projection(status: 'searching', version: 1, sequence: 0),
      projection(status: 'accepted', version: 3, sequence: 2),
    ]);
    expect(seen.map((e) => e.status), [
      RideStatus.findingDriver,
      RideStatus.driverAssigned,
    ]);
    expect(seen.first.sequence, 0);
  });

  test(
    'X6: a bare projection is read, with the driverLocation GeoFix',
    () async {
      final t = build([
        projection(
          status: 'driver_to_pickup',
          version: 4,
          sequence: 4,
          driverLocation: {
            'lat': 59.3301,
            'lng': 18.0602,
            'accuracy': 8,
            'measuredAt': '2026-10-19T09:00:03Z',
          },
        ),
      ]);
      final seen = <RideRealtimeEvent>[];
      final sub = t.rt.subscribe('ride-1').listen(seen.add);
      addTearDown(sub.cancel);
      await settle();
      expect(seen, hasLength(1));
      expect(seen.single.status, RideStatus.driverArriving);
      expect(seen.single.latitude, 59.3301);
      expect(seen.single.longitude, 18.0602);
      expect(
        seen.single.payload['serverLocationAt'],
        '2026-10-19T09:00:03.000Z',
      );
      expect(t.conn.state, RealtimeState.connected);
    },
  );

  test('RC-06: every request sends the contract X-Api-Version', () async {
    final t = build([projection(status: 'searching', version: 1, sequence: 1)]);
    final sub = t.rt.subscribe('ride-1').listen((_) {});
    addTearDown(sub.cancel);
    await settle();
    final headers = contract['headers'] as Map<String, dynamic>;
    expect(ApiClient.apiVersion, headers['X-Api-Version']);
    expect(t.requests.single.headers['X-Api-Version'], '0.5');
  });
}
