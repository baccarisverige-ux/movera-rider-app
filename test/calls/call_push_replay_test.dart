import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/realtime/api_ride_realtime.dart';
import 'package:movera_rider/core/realtime/call_events.dart';

/// Rules REMINDERS row 29 (contract §62 / §78 `inAppCalls.push`): the
/// call push goes to a phone whose trip stream is down; while it is down
/// the trip is polled, and the projection's sequence moves past the
/// call_ringing event (call events bump the trip sequence but carry no
/// projection). When the trip opens from the push the stream must replay
/// after what the stream itself saw, so call_ringing still comes and the
/// incoming-call sheet shows. Fail-before: the reopen asked `after=` the
/// polled sequence and the ringing call was never seen.
void main() {
  const live = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://x.invalid',
  );
  final t0 = DateTime.utc(2026, 11, 11, 9);

  Map<String, Object?> projection(int sequence) => {
    'tripId': 'trp_1',
    'status': 'driver_to_pickup',
    'version': 1,
    'sequence': sequence,
    'updatedAt': t0.toIso8601String(),
    'fare': {'amountMinor': 8600, 'currency': 'SEK'},
    'pickup': {'address': 'Vasagatan 1', 'lat': 59.3293, 'lng': 18.0686},
  };

  String sse(Map<String, Object?> event) =>
      'id: ${event['sequence']}\ndata: ${jsonEncode(event)}\n\n';

  tearDown(() => RideCallEvents.sink = null);

  test('a reconnect replays the call_ringing a poll moved past', () async {
    var sequence = 1;
    final opens = <Uri>[];
    final streams = <StreamController<List<int>>>[];
    final rt = ApiRideRealtime(
      api: ApiClient(
        env: live,
        client: MockClient.streaming((request, _) async {
          if (request.url.path.endsWith('/events')) {
            opens.add(request.url);
            final lines = StreamController<List<int>>();
            streams.add(lines);
            return http.StreamedResponse(lines.stream, 200);
          }
          return http.StreamedResponse(
            Stream.value(utf8.encode(jsonEncode(projection(sequence)))),
            200,
          );
        }),
      ),
      pollInterval: const Duration(milliseconds: 20),
      streamRetryWait: const Duration(milliseconds: 150),
    );
    addTearDown(rt.dispose);
    final calls = <String>[];
    RideCallEvents.sink = (tripId, kind, payload) =>
        calls.add('$tripId:$kind:${payload['callId']}');
    final sub = rt.subscribe('trp_1').listen((_) {});
    addTearDown(sub.cancel);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(opens, hasLength(1));

    // The app goes to the background: the stream drops; the driver calls
    // (sequence 2) and the polls read the trip at sequence 2.
    sequence = 2;
    await streams.first.close();
    await Future<void>.delayed(const Duration(milliseconds: 80));

    // The stream comes back (the trip opened from the push).
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(opens.length, greaterThanOrEqualTo(2));
    expect(
      opens[1].queryParameters['after'],
      '1',
      reason: 'replay after what the stream saw, not the polled sequence',
    );
    streams[1].add(
      utf8.encode(
        sse({
          'eventId': 'ev-2',
          'tripId': 'trp_1',
          'sequence': 2,
          'version': 1,
          'kind': 'call_ringing',
          'occurredAt': t0.toIso8601String(),
          'serverTime': t0.toIso8601String(),
          'call': {'callId': 'call_1', 'tripId': 'trp_1', 'to': 'rider'},
        }),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(calls, ['trp_1:call_ringing:call_1']);
    for (final s in streams) {
      unawaited(s.close());
    }
  });
}
