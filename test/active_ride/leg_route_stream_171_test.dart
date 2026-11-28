import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/realtime/api_ride_realtime.dart';
import 'package:movera_rider/core/realtime/leg_route_hub.dart';
import 'package:movera_rider/core/realtime/realtime_gate.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';

import 'leg_route_171_fixtures.dart';

/// v0.18.170 / v0.18.171 (contract.json#googleRoadLines.rider): the rider
/// gets the leg's stored road line from every trip read (even one the
/// gate drops as not newer) and from TripEta.legRoute on the location
/// events; in memory only; dropped on a driver change, back to searching
/// and a terminal status.
void main() {
  const live = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://x.invalid',
  );
  final t0 = DateTime.utc(2026, 11, 28, 9);

  Map<String, Object?> projection({
    int version = 1,
    int sequence = 1,
    String status = 'driver_to_pickup',
    String driverId = 'drv_1',
    Map<String, Object?>? legRoute,
  }) => {
    'tripId': 'trp_171',
    'status': status,
    'version': version,
    'sequence': sequence,
    'updatedAt': t0.add(Duration(seconds: version)).toIso8601String(),
    'pickup': {'address': 'Sergels torg', 'lat': 59.3326, 'lng': 18.0649},
    'dropoff': {'address': 'Medborgarplatsen', 'lat': 59.3143, 'lng': 18.0735},
    'driver': {'driverId': driverId, 'firstName': 'Ali'},
    'driverLocation': {
      'lat': 59.34,
      'lng': 18.05,
      'measuredAt': t0.toIso8601String(),
    },
    'legRoute': ?legRoute,
  };

  Map<String, Object?> locationEvent(int sequence, {Object? legRoute}) => {
    'eventId': 'ev-$sequence',
    'tripId': 'trp_171',
    'sequence': sequence,
    'version': 1,
    'kind': 'location',
    'occurredAt': t0.add(Duration(seconds: sequence)).toIso8601String(),
    'serverTime': t0.add(Duration(seconds: sequence)).toIso8601String(),
    'location': {
      'lat': 59.339,
      'lng': 18.052,
      'measuredAt': t0.add(Duration(seconds: sequence)).toIso8601String(),
    },
    'eta': {
      'etaSeconds': 200,
      'target': 'pickup',
      'at': t0.add(Duration(seconds: sequence)).toIso8601String(),
      'legRoute': ?legRoute,
    },
  };

  String sse(Map<String, Object?> event) =>
      'id: ${event['sequence']}\ndata: ${jsonEncode(event)}\n\n';

  setUp(LegRouteHub.clear);
  tearDown(LegRouteHub.clear);

  /// A contract-wire transport whose reads answer [read] and whose stream
  /// is [lines] (a new controller per open).
  ({ApiRideRealtime rt, List<StreamController<List<int>>> streams}) follow({
    required Map<String, Object?> Function() read,
  }) {
    final streams = <StreamController<List<int>>>[];
    final rt = ApiRideRealtime(
      api: ApiClient(
        env: live,
        client: MockClient.streaming((request, _) async {
          if (request.url.path.endsWith('/events')) {
            final lines = StreamController<List<int>>();
            streams.add(lines);
            return http.StreamedResponse(lines.stream, 200);
          }
          return http.StreamedResponse(
            Stream.value(utf8.encode(jsonEncode(read()))),
            200,
          );
        }),
      ),
      pollInterval: const Duration(milliseconds: 20),
      streamRetryWait: const Duration(milliseconds: 40),
    );
    addTearDown(() async {
      rt.dispose();
      for (final s in streams) {
        await s.close();
      }
    });
    return (rt: rt, streams: streams);
  }

  Future<void> settle([int ms = 80]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  test('no legRoute at the first read, then present after the location '
      'event; the screens get the ETA without it', () async {
    final f = follow(read: () => projection());
    final events = <RideRealtimeEvent>[];
    final sub = f.rt.subscribe('trp_171').listen(events.add);
    addTearDown(sub.cancel);
    await settle();
    expect(LegRouteHub.legOf('trp_171'), isNull, reason: 'first read: none');

    f.streams.single.add(
      utf8.encode(sse(locationEvent(2, legRoute: pickupLegJson()))),
    );
    await settle();
    final leg = LegRouteHub.legOf('trp_171');
    expect(leg, isNotNull);
    expect(leg!.target, 'pickup');
    expect(leg.points, hasLength(pickupLegPoints.length));
    expect(events.last.kind, RealtimeKind.location);
    final eta = events.last.payload[etaKey];
    expect(eta, isA<Map>());
    expect((eta as Map).containsKey('legRoute'), isFalse);
  });

  test('a same-version re-read (dropped by the gate) still updates the '
      'legRoute', () async {
    var withLine = false;
    final f = follow(
      read: () => projection(legRoute: withLine ? pickupLegJson() : null),
    );
    final events = <RideRealtimeEvent>[];
    final sub = f.rt.subscribe('trp_171').listen(events.add);
    addTearDown(sub.cancel);
    await settle();
    expect(events, hasLength(1));
    withLine = true;
    // The stream drops: the poll reads the same version again.
    await f.streams.single.close();
    await settle();
    expect(events, hasLength(1), reason: 'the projection itself is dropped');
    expect(LegRouteHub.legOf('trp_171')?.target, 'pickup');
  });

  test('stream down during the event: the reconnect read restores the '
      'line', () async {
    var serverHasLine = false;
    final f = follow(
      read: () => projection(legRoute: serverHasLine ? pickupLegJson() : null),
    );
    final sub = f.rt.subscribe('trp_171').listen((_) {});
    addTearDown(sub.cancel);
    await settle();
    expect(LegRouteHub.legOf('trp_171'), isNull);
    // The stream dies; the location event with the line is never seen.
    serverHasLine = true;
    await f.streams.first.close();
    await settle(150);
    expect(LegRouteHub.legOf('trp_171')?.target, 'pickup');
  });

  test(
    'a driver change drops it; the new driver\'s line comes after',
    () async {
      var driver = 'drv_1';
      var version = 1;
      final f = follow(
        read: () => projection(
          version: version,
          sequence: version,
          driverId: driver,
          legRoute: driver == 'drv_1' ? pickupLegJson() : null,
        ),
      );
      final sub = f.rt.subscribe('trp_171').listen((_) {});
      addTearDown(sub.cancel);
      await settle();
      expect(LegRouteHub.legOf('trp_171'), isNotNull);
      driver = 'drv_2';
      version = 2;
      f.streams.single.add(
        utf8.encode(
          sse({
            'eventId': 'ev-swap',
            'tripId': 'trp_171',
            'sequence': 2,
            'version': 2,
            'kind': 'trip_projection',
            'projection': projection(
              version: 2,
              sequence: 2,
              driverId: 'drv_2',
            ),
          }),
        ),
      );
      await settle();
      expect(LegRouteHub.legOf('trp_171'), isNull);
    },
  );

  test('back to searching and a terminal status drop it', () async {
    for (final status in ['searching', 'completed']) {
      LegRouteHub.clear();
      final f = follow(read: () => projection(legRoute: pickupLegJson()));
      final sub = f.rt.subscribe('trp_171').listen((_) {});
      await settle();
      expect(LegRouteHub.legOf('trp_171'), isNotNull, reason: status);
      f.streams.single.add(
        utf8.encode(
          sse({
            'eventId': 'ev-$status',
            'tripId': 'trp_171',
            'sequence': 2,
            'version': 2,
            'kind': 'trip_projection',
            'projection': projection(
              version: 2,
              sequence: 2,
              status: status,
              legRoute: pickupLegJson(),
            ),
          }),
        ),
      );
      await settle();
      expect(LegRouteHub.legOf('trp_171'), isNull, reason: status);
      await sub.cancel();
    }
  });

  test('a legRoute with fewer than 2 points or a bad string is ignored', () {
    expect(
      LegRoute.tryParse({
        'target': 'pickup',
        'polyline': encodeLine(const [LatLng(59.33, 18.06)]),
      }),
      isNull,
    );
    expect(LegRoute.tryParse({'target': 'pickup', 'polyline': '~'}), isNull);
    expect(LegRoute.tryParse({'target': 'pickup', 'polyline': ''}), isNull);
    expect(LegRoute.tryParse({'target': 'moon', 'polyline': 'abc'}), isNull);
    expect(LegRoute.tryParse(pickupLegJson()), isNotNull);
  });

  test('an invalid legRoute on the event keeps the line shown', () async {
    final f = follow(read: () => projection(legRoute: pickupLegJson()));
    final sub = f.rt.subscribe('trp_171').listen((_) {});
    addTearDown(sub.cancel);
    await settle();
    final before = LegRouteHub.legOf('trp_171');
    f.streams.single.add(
      utf8.encode(
        sse(locationEvent(2, legRoute: {'target': 'pickup', 'polyline': '?'})),
      ),
    );
    await settle();
    expect(LegRouteHub.legOf('trp_171'), same(before));
  });
}
