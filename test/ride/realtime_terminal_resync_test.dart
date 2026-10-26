import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/core/realtime/realtime_connection.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/core/contracts/trip_status.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';

class ImmediateRealtimeConnection extends RealtimeConnection {
  @override
  Duration nextBackoff() => Duration.zero;
}

Future<(ApiClient, MockRideRealtime, String)> harness() async {
  final transport = InProcessMockClient();
  final api = ApiClient(client: transport);
  final realtime = MockRideRealtime(
    api: api,
    connection: ImmediateRealtimeConnection(),
    assignAfter: const Duration(days: 1),
  );

  final quoteResponse = await api.post(
    '/api/v1/quotes',
    body: <String, dynamic>{
      'rideType': 'economy',
      'pickup': <String, dynamic>{'lat': 59.3293, 'lng': 18.0686},
      'destination': <String, dynamic>{'lat': 59.3326, 'lng': 18.0649},
    },
  );
  final quote = Map<String, dynamic>.from(quoteResponse['quote'] as Map);
  final created = await api.post(
    '/api/v1/rides',
    body: <String, dynamic>{
      'categoryId': 'economy',
      'price': 259,
      'paymentMethod': 'apple_pay',
      'pickupAddress': 'Pickup',
      'destinationAddress': 'Destination',
      'pickupLat': 59.3293,
      'pickupLng': 18.0686,
      'destinationLat': 59.3326,
      'destinationLng': 18.0649,
      'quoteId': quote['id'],
      'quoteSignedPayload': quote['signedPayload'],
      'quoteExpiresAt': quote['expiresAt'],
      'quoteTotalMinor': quote['totalMinor'],
    },
  );
  final ride = Map<String, dynamic>.from(created['ride'] as Map);
  final rideId = ride['id'] as String;
  realtime.subscribe(rideId);
  realtime.holdAssignment();
  return (api, realtime, rideId);
}

Future<void> setServerStatus(
  ApiClient api,
  String rideId,
  RideStatus status,
) async {
  await api.post(
    '/api/v1/rides/$rideId/status',
    // The simulator walks the trip there through the transition table.
    body: <String, dynamic>{'status': status.tripStatus.wireName},
  );
}

void main() {
  // Contract v0.3.0: every terminal cause the server can reach from a
  // search, by its own UI state (a driver drop before pickup is not one: the
  // trip goes back to searching).
  for (final terminal in <RideStatus>[
    RideStatus.cancelledByRider,
    RideStatus.endedByDriver,
    RideStatus.cancelledBySystem,
    RideStatus.cancelledByAdmin,
    RideStatus.noShow,
    RideStatus.tripFailed,
    RideStatus.noDriverFound,
  ]) {
    test(
      'resync delivers authoritative ${terminal.name} exactly once',
      () async {
        final (api, realtime, rideId) = await harness();
        addTearDown(realtime.dispose);

        final events = <RideRealtimeEvent>[];
        final subscription = realtime.subscribe(rideId).listen(events.add);
        addTearDown(subscription.cancel);

        await setServerStatus(api, rideId, terminal);
        await realtime.reconnectAndResync(rideId);
        await Future<void>.delayed(Duration.zero);

        final terminalEvents = events
            .where((event) => event.status == terminal)
            .toList(growable: false);

        expect(terminalEvents, hasLength(1));
        expect(terminalEvents.single.rideId, rideId);
        expect(realtime.lastStatus, terminal);

        // A second resync after the terminal delivery must not duplicate it.
        await realtime.reconnectAndResync(rideId);
        await Future<void>.delayed(Duration.zero);

        expect(events.where((event) => event.status == terminal), hasLength(1));
      },
    );
  }

  test('resync still delivers a non-terminal authoritative status', () async {
    final (api, realtime, rideId) = await harness();
    addTearDown(realtime.dispose);

    final events = <RideRealtimeEvent>[];
    final subscription = realtime.subscribe(rideId).listen(events.add);
    addTearDown(subscription.cancel);

    await setServerStatus(api, rideId, RideStatus.driverAssigned);
    await realtime.reconnectAndResync(rideId);
    await Future<void>.delayed(Duration.zero);

    expect(
      events.where((event) => event.status == RideStatus.driverAssigned),
      hasLength(1),
    );
    expect(realtime.lastStatus, RideStatus.driverAssigned);
  });
}
