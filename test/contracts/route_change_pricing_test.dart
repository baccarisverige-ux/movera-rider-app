import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';

/// Contract v0.4.3 §3 "Route-change pricing" on the stand-in server (owner
/// decision 5): a route change is priced from the booking (fare, offer
/// raises, route through its stops), and only stops that were not booked
/// pay the stop fee. Server seam.
void main() {
  late InProcessMockClient server;
  late ApiClient api;

  setUp(() {
    server = InProcessMockClient();
    api = ApiClient(client: server);
  });

  const stop = {'address': 'Stop', 'lat': 59.35, 'lng': 18.10};
  Map<String, dynamic> route({List<Map<String, Object>> stops = const [stop]}) =>
      {
        'pickupAddress': 'Pickup',
        'pickupLat': 59.3293,
        'pickupLng': 18.0686,
        'destinationAddress': 'Destination',
        'destinationLat': 59.3326,
        'destinationLng': 18.0649,
        'stops': stops,
      };

  Future<String> book() async {
    final quote = (await api.post(
      '/api/v1/quotes',
      body: {'rideType': 'economy', ...route()},
    ))['quote'] as Map;
    final created = await api.post(
      '/api/v1/rides',
      body: {
        'categoryId': 'economy',
        'fare': {'amountMinor': quote['totalMinor'], 'currency': 'SEK'},
        'paymentMethodId': 'card',
        ...route(),
        'quoteId': quote['id'],
        'quoteSignedPayload': quote['signedPayload'],
        'quoteExpiresAt': quote['expiresAt'],
        'quoteTotalMinor': quote['totalMinor'],
      },
    );
    return (created['ride'] as Map)['id'] as String;
  }

  Future<Map<String, dynamic>> requote(
    String id, {
    List<Map<String, Object>> stops = const [stop],
  }) => api.post('/api/v1/rides/$id/route-quote', body: route(stops: stops));

  int fareOf(String id) => (server.rides[id]!['fare'] as Map)['amountMinor'] as int;

  test('rider-9: re-quoting the booked multi-stop route costs nothing more; '
      'only a new stop pays the stop fee', () async {
    final id = await book();
    final same = await requote(id);
    expect(same['differenceMinor'], 0);
    expect(same['newTotalMinor'], fareOf(id));

    // A second stop next to the booked one: the stop fee once, for it alone.
    final more = await requote(id, stops: [
      stop,
      {'address': 'Next door', 'lat': 59.3501, 'lng': 18.1001},
    ]);
    expect(more['differenceMinor'], inInclusiveRange(2500, 2600));
  });

  test('rider-u14: a route change keeps the offer raise the rider paid',
      () async {
    final id = await book();
    final booked = fareOf(id);
    await api.patch('/api/v1/rides/$id', body: {
      'offerIncrease': {'amountMinor': 5000, 'currency': 'SEK'},
    });
    await api.patch('/api/v1/rides/$id', body: {
      'offerIncrease': {'amountMinor': 2000, 'currency': 'SEK'},
    });
    await api.post('/api/v1/rides/$id/status', body: {'status': 'accepted'});
    final same = await requote(id);
    expect(same['newTotalMinor'], booked + 7000);
    expect(same['differenceMinor'], 0);

    // Dropping the booked stop gives back distance only, never the raise.
    final shorter = await requote(id, stops: const []);
    expect(
      shorter['newTotalMinor'] as int,
      greaterThanOrEqualTo((booked + 7000) ~/ 2),
    );
    expect(shorter['differenceMinor'] as int, isNegative);
  });
}
