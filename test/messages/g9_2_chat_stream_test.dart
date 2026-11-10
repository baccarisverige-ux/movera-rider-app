import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/realtime/api_ride_realtime.dart';
import 'package:movera_rider/core/realtime/call_events.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';

/// Contract v0.18.56 §78 `chat.stream`: the trip stream's `message` events
/// go to the trip chat (badge + open chat); the realtime gate admits their
/// sequence (a replay is dropped, no gap later) and they never change the
/// trip.
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

  test(
    'a message event reaches the chat once and the trip is not re-read',
    () async {
      var reads = 0;
      final lines = StreamController<List<int>>();
      addTearDown(lines.close);
      final got = <String>[];
      RideMessageEvents.sink = (trip, message) =>
          got.add('$trip:${message['messageId']}');
      addTearDown(() => RideMessageEvents.sink = null);
      final rt = ApiRideRealtime(
        api: ApiClient(
          env: live,
          client: MockClient.streaming((request, _) async {
            if (request.url.path.endsWith('/events')) {
              return http.StreamedResponse(lines.stream, 200);
            }
            reads += 1;
            return http.StreamedResponse(
              Stream.value(utf8.encode(jsonEncode(projection()))),
              200,
            );
          }),
        ),
        pollInterval: const Duration(milliseconds: 30),
      );
      addTearDown(rt.dispose);
      final events = <RideRealtimeEvent>[];
      final sub = rt.subscribe('trp_1').listen(events.add);
      addTearDown(sub.cancel);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(reads, 1);
      final message = {
        'eventId': 'ev-2',
        'tripId': 'trp_1',
        'sequence': 2,
        'version': 1,
        'kind': 'message',
        'occurredAt': t0.toIso8601String(),
        'message': {
          'messageId': 'msg_1',
          'tripId': 'trp_1',
          'from': 'driver',
          'text': "I've arrived",
          'at': t0.toIso8601String(),
          'auto': 'arrived',
        },
      };
      lines.add(utf8.encode(sse(message)));
      // A replay of the same event is dropped by the gate.
      lines.add(utf8.encode(sse(message)));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(got, ['trp_1:msg_1']);
      expect(events, hasLength(1), reason: 'a message never changes the trip');
      // The next trip event follows the message's sequence: no gap, no read.
      lines.add(
        utf8.encode(
          sse({
            'eventId': 'ev-3',
            'tripId': 'trp_1',
            'sequence': 3,
            'version': 2,
            'kind': 'trip_projection',
            'occurredAt': t0.toIso8601String(),
            'projection': projection(version: 2, sequence: 3),
          }),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(events, hasLength(2));
      expect(reads, 1, reason: 'no gap resync after the message sequence');
    },
  );
}
