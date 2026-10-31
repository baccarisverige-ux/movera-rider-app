import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/realtime/api_ride_realtime.dart';
import 'package:movera_rider/core/realtime/realtime_gate.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';

/// Driver group 5, contract v0.18.7 `pickupWaiting.follow`: the rider app
/// no longer polls the trip every 2 s. On the contract wire the trip is
/// read once, then followed on its stream (`GET /trips/{tripId}/events`);
/// the projection is polled only while the stream is down, every 10 s,
/// never under 5. The ETA tick rides on the stream as a `location` event
/// with `eta`; `pickup_moved` is accepted like `trip_projection`.
void main() {
  const live = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://x.invalid',
  );
  final t0 = DateTime.utc(2026, 10, 31, 9);

  Map<String, Object?> projection({
    int version = 1,
    int sequence = 1,
    String status = 'driver_to_pickup',
    Map<String, Object?>? pickup,
  }) => {
    'tripId': 'trp_1',
    'status': status,
    'version': version,
    'sequence': sequence,
    'updatedAt': t0.add(Duration(seconds: version)).toIso8601String(),
    'fare': {'amountMinor': 8600, 'currency': 'SEK'},
    'pickup':
        pickup ?? {'address': 'Vasagatan 1', 'lat': 59.3293, 'lng': 18.0686},
    'driverLocation': {
      'lat': 59.34,
      'lng': 18.05,
      'accuracy': 5,
      'measuredAt': t0.toIso8601String(),
    },
    'eta': {
      'etaSeconds': 250,
      'distanceMeters': 1234,
      'target': 'pickup',
      'at': t0.toIso8601String(),
      'source': 'osrm',
    },
    'terms': {
      'currency': 'SEK',
      'freeWaitMin': 5,
      'waitPerMin': {'amountMinor': 1226, 'currency': 'SEK'},
      'noShowAfterMin': 5,
      'noShowFee': {'amountMinor': 6500, 'currency': 'SEK'},
      'cancelRule': {
        'freeMin': 2,
        'type': 'fixed',
        'value': 3500,
        'min': null,
        'max': null,
      },
      'cancelAfterArrivedIsNoShow': true,
      'maxPickupMoveMeters': 200,
    },
  };

  String sse(Map<String, Object?> event) =>
      'id: ${event['sequence']}\ndata: ${jsonEncode(event)}\n\n';

  test('the default cadence is 10 s, never under 5 (no 2 s poll)', () {
    expect(ApiRideRealtime.defaultPollInterval, const Duration(seconds: 10));
    expect(
      ApiRideRealtime.defaultPollInterval >= ApiRideRealtime.minPollInterval,
      isTrue,
    );
    expect(ApiRideRealtime.minPollInterval, const Duration(seconds: 5));
  });

  test('contract wire: one read, then the stream; no poll while it is up; the '
      'ETA tick and a pickup move arrive as events', () async {
    var reads = 0;
    var streams = 0;
    final lines = StreamController<List<int>>();
    addTearDown(lines.close);
    final rt = ApiRideRealtime(
      api: ApiClient(
        env: live,
        client: MockClient.streaming((request, _) async {
          if (request.url.path.endsWith('/events')) {
            streams += 1;
            expect(request.headers['Accept'], 'text/event-stream');
            return http.StreamedResponse(lines.stream, 200);
          }
          reads += 1;
          expect(request.url.path, '/api/v1/trips/trp_1');
          return http.StreamedResponse(
            Stream.value(utf8.encode(jsonEncode(projection()))),
            200,
          );
        }),
      ),
      pollInterval: const Duration(milliseconds: 30),
    );
    addTearDown(rt.dispose);
    expect(rt.followStream, isTrue);
    final events = <RideRealtimeEvent>[];
    final sub = rt.subscribe('trp_1').listen(events.add);
    addTearDown(sub.cancel);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(reads, 1, reason: 'read once, then the stream');
    expect(streams, 1);
    expect(rt.isStreamUp('trp_1'), isTrue);
    expect(events, hasLength(1));
    final first = events.single;
    expect(first.status, RideStatus.driverArriving);
    expect(first.eta?.distanceMeters, 1234);
    expect(first.terms?.maxPickupMoveMeters, 200);
    expect(first.pickup?.address, 'Vasagatan 1');

    // The ETA tick (every 30 s on the server): a location event with eta,
    // no version change, never replacing the projection.
    lines.add(
      utf8.encode(
        sse({
          'eventId': 'ev-2',
          'tripId': 'trp_1',
          'sequence': 2,
          'version': 1,
          'kind': 'location',
          'occurredAt': t0.add(const Duration(seconds: 30)).toIso8601String(),
          'serverTime': t0.add(const Duration(seconds: 30)).toIso8601String(),
          'location': {
            'lat': 59.338,
            'lng': 18.06,
            'accuracy': 5,
            'measuredAt': t0.add(const Duration(seconds: 29)).toIso8601String(),
          },
          'etaSeconds': 190,
          'eta': {
            'etaSeconds': 190,
            'distanceMeters': 850,
            'target': 'pickup',
            'at': t0.add(const Duration(seconds: 30)).toIso8601String(),
            'source': 'osrm',
          },
        }),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(events, hasLength(2));
    final tick = events.last;
    expect(tick.kind, RealtimeKind.location);
    expect(tick.status, RideStatus.driverArriving, reason: 'status kept');
    expect(tick.version, 1);
    expect(tick.latitude, 59.338);
    expect(tick.etaSeconds, 190);
    expect(tick.eta?.distanceMeters, 850);

    // The rider moved the pickup: pickup_moved carries the projection.
    lines.add(
      utf8.encode(
        sse({
          'eventId': 'ev-3',
          'tripId': 'trp_1',
          'sequence': 3,
          'version': 2,
          'kind': 'pickup_moved',
          'occurredAt': t0.add(const Duration(seconds: 40)).toIso8601String(),
          'serverTime': t0.add(const Duration(seconds: 40)).toIso8601String(),
          'projection': projection(
            version: 2,
            sequence: 3,
            pickup: {'address': 'Vasagatan 9', 'lat': 59.3302, 'lng': 18.069},
          ),
        }),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(events, hasLength(3));
    expect(events.last.kind, RealtimeKind.pickupMoved);
    expect(events.last.version, 2);
    expect(events.last.pickup?.address, 'Vasagatan 9');
    expect(reads, 1, reason: 'still no poll while the stream is up');
  });

  test('while the stream is down the trip is polled every 10 s, and the stream '
      'is tried again; once it is up the polling stops', () {
    fakeAsync((async) {
      var now = t0;
      var reads = 0;
      var streamsTried = 0;
      var streamDown = true;
      final rt = ApiRideRealtime(
        api: ApiClient(
          env: live,
          client: MockClient.streaming((request, _) async {
            if (request.url.path.endsWith('/events')) {
              streamsTried += 1;
              if (streamDown) {
                return http.StreamedResponse(
                  Stream.value(utf8.encode('{"code":"unavailable"}')),
                  503,
                );
              }
              return http.StreamedResponse(
                StreamController<List<int>>().stream,
                200,
              );
            }
            reads += 1;
            return http.StreamedResponse(
              Stream.value(utf8.encode(jsonEncode(projection()))),
              200,
            );
          }),
        ),
        clock: () => now,
      );
      final events = <RideRealtimeEvent>[];
      final sub = rt.subscribe('trp_1').listen(events.add);
      async.flushMicrotasks();
      expect(reads, 1);
      expect(streamsTried, 1);
      expect(rt.isStreamUp('trp_1'), isFalse);
      expect(events, hasLength(1));

      void tick(int seconds) {
        for (var s = 0; s < seconds; s += 1) {
          now = now.add(const Duration(seconds: 1));
          async.elapse(const Duration(seconds: 1));
        }
      }

      tick(9);
      expect(reads, 1, reason: 'no poll before 10 s (never 2 s)');
      tick(2);
      expect(reads, 2, reason: 'one poll at 10 s');
      tick(10);
      expect(reads, 3);
      expect(streamsTried, greaterThan(1), reason: 'the stream is retried');

      // The server's stream is back: the next retry connects and the poll
      // timer stops.
      streamDown = false;
      // The retries back off (5, 10, 20 s …): the next one connects.
      tick(20);
      expect(rt.isStreamUp('trp_1'), isTrue);
      final readsWhenUp = reads;
      tick(30);
      expect(reads, readsWhenUp, reason: 'no polling while the stream is up');
      sub.cancel();
      rt.dispose();
    });
  });

  test('the demo wire (no stream) keeps polling, now at the 10 s default', () {
    fakeAsync((async) {
      var reads = 0;
      final rt = ApiRideRealtime(
        api: ApiClient(
          env: AppEnv.current,
          client: MockClient((_) async {
            reads += 1;
            return http.Response(
              jsonEncode({'ride': projection(version: reads)}),
              200,
            );
          }),
        ),
      );
      expect(rt.followStream, isFalse);
      final sub = rt.subscribe('trp_1').listen((_) {});
      async.flushMicrotasks();
      expect(reads, 1);
      async.elapse(const Duration(seconds: 9));
      expect(reads, 1);
      async.elapse(const Duration(seconds: 2));
      expect(reads, 2);
      sub.cancel();
      rt.dispose();
    });
  });
}
