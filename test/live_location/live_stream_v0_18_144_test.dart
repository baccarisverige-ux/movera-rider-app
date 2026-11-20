import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/realtime/api_ride_realtime.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/active_ride/application/live_location_share.dart';

/// Contract v0.18.144 (`contract.json#liveLocation.relay`): the rider opens
/// the trip stream with ?live=true; a `live_location` frame (no id) goes to
/// [LiveLocationHub], never into the trip events.
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

  test('?live=true, and a live frame reaches the hub, not the trip events', () async {
    final lines = StreamController<List<int>>();
    addTearDown(lines.close);
    Uri? streamUrl;
    final rt = ApiRideRealtime(
      api: ApiClient(
        env: live,
        client: MockClient.streaming((request, _) async {
          if (request.url.path.endsWith('/events')) {
            streamUrl = request.url;
            return http.StreamedResponse(lines.stream, 200);
          }
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
    final frames = <LiveLocationFrame>[];
    final sub = rt.subscribe('trp_1').listen(events.add);
    final hub = LiveLocationHub.of('trp_1').listen(frames.add);
    addTearDown(sub.cancel);
    addTearDown(hub.cancel);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(streamUrl?.queryParameters['live'], 'true');
    final before = events.length;
    lines.add(
      utf8.encode(
        'event: live_location\ndata: ${jsonEncode({'tripId': 'trp_1', 'side': 'driver', 'sharing': true, 'lat': 59.33, 'lng': 18.06, 'at': t0.toIso8601String()})}\n\n',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(frames.single.side, 'driver');
    expect(events.length, before, reason: 'a live point is not a trip event');
  });
}
