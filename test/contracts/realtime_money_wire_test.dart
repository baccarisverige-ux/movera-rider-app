import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/realtime/api_ride_realtime.dart';
import 'package:movera_rider/core/realtime/realtime_gate.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/ride_booking/data/mock_quote_repository.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/quote.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';

/// Contract v0.3.0 on the stand-in wire: server-assigned realtime sequence,
/// Money instead of kronor doubles, and quotes that carry the stops.
void main() {
  late InProcessMockClient server;
  late ApiClient api;

  setUp(() {
    server = InProcessMockClient();
    api = ApiClient(client: server);
  });

  Future<String> book() async {
    final quote =
        (await api.post(
              '/api/v1/quotes',
              body: {
                'rideType': 'economy',
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
        'categoryId': 'economy',
        'fare': {'amountMinor': quote['totalMinor'], 'currency': 'SEK'},
        'paymentMethodId': 'card',
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
    return (created['ride'] as Map)['id'] as String;
  }

  Future<void> simulate(String id, Map<String, dynamic> body) =>
      api.post('/api/v1/rides/$id/status', body: body);

  /// Every key in [json], at any depth.
  Iterable<String> keys(Object? json) sync* {
    if (json is Map) {
      for (final entry in json.entries) {
        yield '${entry.key}';
        yield* keys(entry.value);
      }
    } else if (json is List) {
      for (final item in json) {
        yield* keys(item);
      }
    }
  }

  test(
    'the server assigns sequence and eventId; the client keeps them',
    () async {
      final id = await book();
      final realtime = ApiRideRealtime(
        api: api,
        pollInterval: const Duration(days: 1),
      );
      addTearDown(realtime.dispose);
      final events = <RideRealtimeEvent>[];
      final sub = realtime.subscribe(id).listen(events.add);
      addTearDown(sub.cancel);
      await Future<void>.delayed(Duration.zero);
      await simulate(id, {'status': 'accepted'}); // offered, accepted: +2
      await realtime.reconnectAndResync(id);
      await simulate(id, {'status': 'completed'});
      await realtime.reconnectAndResync(id);
      await simulate(id, {'paymentStatus': 'captured'});
      await realtime.reconnectAndResync(id);
      // A lifecycle change after the terminal status is blocked by the gate:
      // the stand-in server cannot produce one, so replay the same poll.
      await realtime.reconnectAndResync(id);
      await Future<void>.delayed(Duration.zero);

      final ride = server.rides[id]!;
      expect(events.map((e) => e.sequence), [1, 3, 8, 9]);
      expect(events.last.sequence, ride['sequence']);
      expect(events.last.eventId, ride['eventId']);
      expect(events.map((e) => e.kind).last, RealtimeKind.paymentUpdated);
      expect(events.map((e) => e.eventId).toSet(), hasLength(events.length));
    },
  );

  test('ride, offer and route-change money is Money, never kronor', () async {
    final id = await book();
    final booked = server.rides[id]!;
    expect(booked['fare'], isA<Map>());
    expect((booked['fare'] as Map)['currency'], 'SEK');

    final raised = await api.patch(
      '/api/v1/rides/$id',
      body: {
        'offerIncrease': {'amountMinor': 2000, 'currency': 'SEK'},
      },
    );
    final fare = ((raised['ride'] as Map)['fare'] as Map)['amountMinor'] as int;
    expect(fare, ((booked['bookedFare'] as Map)['amountMinor'] as int) + 2000);

    await simulate(id, {'status': 'driver_to_pickup'});
    final quote = await api.post(
      '/api/v1/rides/$id/route-quote',
      body: {
        'destinationAddress': 'Further',
        'destinationLat': 59.35,
        'destinationLng': 18.07,
        'stops': [
          {'address': 'Stop', 'lat': 59.34, 'lng': 18.06},
        ],
      },
    );
    expect(quote['newTotal'], isA<Map>());
    final applied = await api.patch(
      '/api/v1/rides/$id',
      body: {
        'routeChange': true,
        'routeQuoteId': quote['routeQuoteId'],
        'destinationAddress': 'Further',
        'destinationLat': 59.35,
        'destinationLng': 18.07,
        'stops': [
          {'address': 'Stop', 'lat': 59.34, 'lng': 18.06},
        ],
        'expectedTotalMinor': quote['newTotalMinor'],
        'paymentMethodId': 'card',
      },
    );
    final wire = [quote, applied, server.rides[id]];
    final majorKeys = keys(wire).where(
      (key) => key == 'price' || key == 'bookedPrice' || key.endsWith('Kr'),
    );
    expect(majorKeys, isEmpty);
  });

  test('Select ride quotes carry the stops', () async {
    final quotes = _RecordingQuotes();
    final selection = RideSelectionController(quotes: quotes);
    const stop = RouteStop(address: 'Stop', latitude: 59.34, longitude: 18.06);
    await selection.loadQuotes(
      generation: selection.beginQuotes(),
      pickup: 'A',
      destination: 'B',
      stops: const [stop],
    );
    expect(quotes.stops, isNotEmpty);
    expect(
      quotes.stops.every((s) => s.length == 1 && s.single == stop),
      isTrue,
    );
    await selection.quoteFromPin(
      rideId: 'economy',
      distanceMeters: 1,
      stops: const [stop],
    );
    expect(quotes.stops.last, [stop]);
  });
}

class _RecordingQuotes implements QuoteRepository {
  final stops = <List<RouteStop>>[];

  @override
  Future<RideQuote> quote({
    required String rideType,
    required int distanceMeters,
    int durationSeconds = 600,
    String? pickup,
    String? destination,
    GeoPoint? pickupPoint,
    GeoPoint? destinationPoint,
    List<RouteStop> stops = const <RouteStop>[],
  }) async {
    this.stops.add(stops);
    return RideQuote(
      id: 'q_$rideType',
      rideType: rideType,
      totalMinor: 25900,
      currency: 'SEK',
      expiresAt: DateTime.now().add(const Duration(minutes: 2)),
      baseMinor: 25900,
    );
  }
}
