import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/contracts/ride_status.dart';
import 'package:movera_rider/core/contracts/trip_status.dart';
import 'package:movera_rider/core/realtime/api_ride_realtime.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';

/// The stand-in server keeps the contract lifecycle (v0.3.0): snake_case
/// status, tripId, and every change through the transition table.
void main() {
  late InProcessMockClient server;
  late ApiClient api;

  setUp(() {
    server = InProcessMockClient();
    api = ApiClient(client: server);
  });

  Future<Map<String, dynamic>> book({String category = 'movera'}) async {
    final quote =
        (await api.post(
              '/api/v1/quotes',
              body: {
                'rideType': category,
                'pickupLat': 59.3293,
                'pickupLng': 18.0686,
                'destinationLat': 59.3326,
                'destinationLng': 18.0649,
              },
            ))['quote']
            as Map;
    final created = await api.post(
      '/api/v1/rides',
      body: {
        'categoryId': category,
        'price': (quote['totalMinor'] as int) / 100,
        'paymentMethodId': 'cash',
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
    return Map<String, dynamic>.from(created['ride'] as Map);
  }

  Future<Map<String, dynamic>> simulate(
    String id,
    Map<String, dynamic> body,
  ) async => Map<String, dynamic>.from(
    (await api.post('/api/v1/rides/$id/status', body: body))['ride'] as Map,
  );

  test(
    'a live booking is created searching, with tripId and economy',
    () async {
      final ride = await book();
      expect(ride['status'], 'searching');
      expect(ride['tripId'], ride['id']);
      expect(ride['rideId'], ride['id']);
      expect(ride['categoryId'], 'economy', reason: 'movera is an alias');
      expect(ride['ratingStatus'], 'not_requested');
    },
  );

  test(
    'cancel after completion is 409 invalid_transition with projection',
    () async {
      final ride = await book();
      final id = ride['id'] as String;
      final done = await simulate(id, {'status': 'completed'});
      expect(done['status'], 'completed');
      expect(done['version'], greaterThan(ride['version'] as int));

      final error = await api
          .post(
            '/api/v1/rides/$id/cancel',
            body: {'reasonCode': 'plans_changed'},
          )
          .then<ApiError?>((_) => null, onError: (Object e) => e as ApiError);
      expect(error, isNotNull);
      expect(error!.statusCode, 409);
      expect(error.code, 'invalid_transition');
      expect(server.rides[id]!['status'], 'completed');
    },
  );

  test('rider cancel before boarding; end-early once on board', () async {
    final first = await book();
    final cancelled = await api.post(
      '/api/v1/rides/${first['id']}/cancel',
      body: {'reasonCode': 'plans_changed'},
    );
    final ride = cancelled['ride'] as Map;
    expect(ride['status'], 'cancelled_by_rider');
    expect((ride['cancellation'] as Map)['reasonCode'], 'plans_changed');

    final second = await book();
    final id = second['id'] as String;
    await simulate(id, {'status': 'in_trip'});
    await expectLater(
      api.post(
        '/api/v1/rides/$id/cancel',
        body: {'reasonCode': 'plans_changed'},
      ),
      throwsA(
        isA<ApiError>().having((e) => e.code, 'code', 'invalid_transition'),
      ),
    );
    final ended = await api.post('/api/v1/rides/$id/end-early');
    expect((ended['ride'] as Map)['status'], 'cancelled_by_rider');
  });

  test('a driver drop before pickup returns the trip to searching', () async {
    final ride = await book();
    final id = ride['id'] as String;
    await simulate(id, {
      'status': 'driver_to_pickup',
      'driver': {'id': 'd1', 'firstName': 'Ana'},
    });
    final back = await simulate(id, {'command': 'cancel', 'actor': 'driver'});
    expect(back['status'], 'searching');
    expect(back.containsKey('driver'), isFalse);
    // Not a terminal status brought back to life: dispatch goes on.
    final again = await simulate(id, {'status': 'accepted'});
    expect(again['status'], 'accepted');
  });

  test('payment and rating move as fields after completion', () async {
    final ride = await book();
    final id = ride['id'] as String;
    await simulate(id, {'status': 'completed'});
    final paid = await simulate(id, {'paymentStatus': 'captured'});
    expect(paid['status'], 'completed');
    expect(paid['paymentStatus'], 'captured');
    final rating = await simulate(id, {'ratingStatus': 'pending'});
    expect(rating['ratingStatus'], 'pending');
    // Q38 / X20: whole stars only; a half star is refused.
    await expectLater(
      api.post('/api/v1/rides/$id/feedback', body: {'rating': 4.5}),
      throwsA(anything),
    );
    expect(server.rides[id]!['ratingStatus'], 'pending');
    await api.post('/api/v1/rides/$id/feedback', body: {'rating': 4});
    expect(server.rides[id]!['ratingStatus'], 'submitted');
    expect(
      TripStatusWire.parse(server.rides[id]!['status']),
      TripStatus.completed,
    );
  });

  test('search expiry is the expire command, not a client guess', () async {
    final short = InProcessMockClient(searchExpiresAfter: Duration.zero);
    final client = ApiClient(client: short);
    api = client;
    final ride = await book();
    final read = await client.get('/api/v1/rides/${ride['id']}');
    expect((read['ride'] as Map)['status'], 'expired');
  });

  test('polling shows a driver drop as the reassignment notice, not a '
      'terminal status', () async {
    final ride = await book();
    final id = ride['id'] as String;
    final realtime = ApiRideRealtime(
      api: api,
      pollInterval: const Duration(days: 1),
    );
    addTearDown(realtime.dispose);
    final events = <RideRealtimeEvent>[];
    final sub = realtime.subscribe(id).listen(events.add);
    addTearDown(sub.cancel);
    await simulate(id, {'status': 'driver_to_pickup'});
    await realtime.reconnectAndResync(id);
    await simulate(id, {'command': 'cancel', 'actor': 'driver'});
    await realtime.reconnectAndResync(id);
    await Future<void>.delayed(Duration.zero);
    expect(events.map((e) => e.status), [
      RideStatus.findingDriver,
      RideStatus.driverArriving,
      RideStatus.cancelledByDriver,
    ]);
    expect(events.last.payload['tripStatus'], 'searching');
    expect(server.rides[id]!['status'], 'searching');
  });
}
