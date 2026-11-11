import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/realtime/api_ride_realtime.dart';
import 'package:movera_rider/core/realtime/call_events.dart';

/// R09 N1 (B8): call events take trip sequences on the server. The gate
/// must learn them, so the location event after a call burst is not a
/// false gap that forces GET /trips/{id}. Fail-before: one forced read.
///
/// Based on rider job J12 (contract §4 replay, §62/§78 calls): a brand-new trip
/// stream (no cursor) gets the server's whole replay of the trip, old
/// call_ringing events included. A call_ringing older than the longest
/// ring the contract allows (`inAppCalls` ringSeconds ≤ 120 s, measured on
/// the server clock: serverTime − occurredAt) can no longer be ringing, so
/// it must not reach the calls hub (no old incoming-call sheet). A fresh
/// call_ringing still comes. Fail-before: every replayed ring was passed on.
void main() {
  const live = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://x.invalid',
  );
  final now = DateTime.utc(2026, 11, 11, 9);

  Map<String, Object?> projection() => {
    'tripId': 'trp_1',
    'status': 'driver_to_pickup',
    'version': 1,
    'sequence': 1,
    'updatedAt': now.toIso8601String(),
    'fare': {'amountMinor': 8600, 'currency': 'SEK'},
    'pickup': {'address': 'Vasagatan 1', 'lat': 59.3293, 'lng': 18.0686},
  };

  Map<String, Object?> event(int seq, String kind, String id, DateTime at) => {
    'eventId': 'ev-$seq',
    'tripId': 'trp_1',
    'sequence': seq,
    'version': 1,
    'kind': kind,
    'occurredAt': at.toIso8601String(),
    'serverTime': now.toIso8601String(),
    'call': {'callId': id, 'tripId': 'trp_1', 'from': 'driver', 'to': 'rider'},
  };

  String sse(Map<String, Object?> e) =>
      'id: ${e['sequence']}\ndata: ${jsonEncode(e)}\n\n';

  tearDown(() => RideCallEvents.sink = null);

  test('call events do not make the next location a gap', () async {
    final streams = <StreamController<List<int>>>[];
    var tripReads = 0;
    final rt = ApiRideRealtime(
      api: ApiClient(
        env: live,
        client: MockClient.streaming((request, _) async {
          if (request.url.path.endsWith('/events')) {
            final lines = StreamController<List<int>>();
            streams.add(lines);
            return http.StreamedResponse(lines.stream, 200);
          }
          if (request.url.path.endsWith('/trips/trp_1')) tripReads++;
          return http.StreamedResponse(
            Stream.value(utf8.encode(jsonEncode(projection()))),
            200,
          );
        }),
      ),
      pollInterval: const Duration(minutes: 5),
      streamRetryWait: const Duration(milliseconds: 150),
    );
    addTearDown(rt.dispose);
    final calls = <String>[];
    RideCallEvents.sink = (tripId, kind, payload) =>
        calls.add('$kind:${payload['callId']}');
    final sub = rt.subscribe('trp_1').listen((_) {});
    addTearDown(sub.cancel);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(streams, hasLength(1));
    final before = tripReads;
    expect(before, greaterThan(0), reason: 'the first read happened');
    final location = {
      'eventId': 'ev-5',
      'tripId': 'trp_1',
      'sequence': 5,
      'version': 1,
      'kind': 'location',
      'occurredAt': now.toIso8601String(),
      'serverTime': now.toIso8601String(),
      'location': {'lat': 59.33, 'lng': 18.06},
    };
    streams.first.add(
      utf8.encode(
        sse(event(2, 'call_ringing', 'call_1', now)) +
            sse(event(3, 'call_answered', 'call_1', now)) +
            sse(event(4, 'call_ended', 'call_1', now)) +
            sse(location),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(calls, [
      'call_ringing:call_1',
      'call_answered:call_1',
      'call_ended:call_1',
    ], reason: 'call handling is unchanged');
    expect(tripReads, before, reason: 'no false gap, no forced trip read');
    for (final s in streams) {
      unawaited(s.close());
    }
  });
}
