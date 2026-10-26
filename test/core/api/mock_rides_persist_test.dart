import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// rider-r5-2: the demo stand-in server keeps the on-board distance and the
/// accepted pickup across a reload, not only the trips.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the on-board distance survives a reload', () async {
    final first = InProcessMockClient(persistRides: true);
    final api = ApiClient(client: first);
    final quote =
        (await api.post(
              '/api/v1/quotes',
              body: {
                'rideType': 'economy',
                'pickupLat': 59.3293,
                'pickupLng': 18.0686,
                'destinationLat': 59.40,
                'destinationLng': 18.0686,
              },
            ))['quote']
            as Map;
    final id =
        ((await api.post(
                  '/api/v1/rides',
                  body: {
                    'categoryId': 'economy',
                    'price': (quote['totalMinor'] as int) / 100,
                    'paymentMethodId': 'cash',
                    'pickupAddress': 'P',
                    'destinationAddress': 'D',
                    'pickupLat': 59.3293,
                    'pickupLng': 18.0686,
                    'destinationLat': 59.40,
                    'destinationLng': 18.0686,
                    'quoteId': quote['id'],
                    'quoteSignedPayload': quote['signedPayload'],
                    'quoteExpiresAt': quote['expiresAt'],
                    'quoteTotalMinor': quote['totalMinor'],
                  },
                ))['ride']
                as Map)['id']
            as String;
    await api.post(
      '/api/v1/rides/$id/status',
      body: {'status': 'in_trip', 'lat': 59.3293, 'lng': 18.0686},
    );
    await api.post(
      '/api/v1/rides/$id/status',
      body: {'lat': 59.3383, 'lng': 18.0686},
    );
    expect(first.drivenMetersOf(id), closeTo(1000, 10));

    final reloaded = InProcessMockClient(persistRides: true);
    await ApiClient(client: reloaded).get('/api/v1/rides/$id');
    expect(reloaded.drivenMetersOf(id), closeTo(1000, 10));
  });
}
