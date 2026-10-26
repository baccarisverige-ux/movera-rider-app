import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/contracts/matched_driver.dart';
import 'package:movera_rider/features/booking/application/booking_coordinator.dart';
import 'package:movera_rider/features/finding_driver/data/pending_cancel_store.dart';
import 'package:movera_rider/features/ride_complete/data/ride_feedback_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Wave 4 R4.10: what the rider sends and reads on the contract wire.
void main() {
  group('rider-16 contract DriverSummary', () {
    const elin = MatchedDriver(
      id: 'drv_204',
      firstName: 'Elin',
      rating: 4.9,
      vehicleMake: 'Volvo',
      vehicleModel: 'XC40',
      vehicleColor: 'White',
      plate: 'MVR 204',
    );

    test('a DriverSummary with driverId and a nested vehicle parses', () {
      final driver = MatchedDriver.fromJson({
        'driverId': 'drv_204',
        'firstName': 'Elin',
        'rating': 4.9,
        'vehicle': {
          'make': 'Volvo',
          'model': 'XC40',
          'color': 'White',
          'plate': 'MVR 204',
        },
      });
      expect(driver?.id, 'drv_204');
      expect(driver?.plate, 'MVR 204');
      expect(driver?.vehicleLabel, 'White Volvo XC40');
    });

    test('toJson writes the contract shape; legacy flat keys still parse', () {
      final json = elin.toJson();
      expect(json['driverId'], 'drv_204');
      expect(json['vehicle'], {
        'make': 'Volvo',
        'model': 'XC40',
        'color': 'White',
        'plate': 'MVR 204',
      });
      expect(MatchedDriver.fromJson(json)?.vehicleLabel, 'White Volvo XC40');
      final legacy = MatchedDriver.fromJson({
        'id': 'd1',
        'firstName': 'Ana',
        'plate': 'ABC 123',
      });
      expect(legacy?.id, 'd1');
      expect(legacy?.plate, 'ABC 123');
    });
  });

  group('rider-u19 every rider cancel names a contract reasonCode', () {
    test('cancel-first (no reason picked yet) still sends one', () {
      expect(const PendingCancel(rideId: 'r1', expectedVersion: 3).body(), {
        'reasonCode': 'something_else',
        'expectedVersion': 3,
      });
    });

    test('a 400 refusal is final instead of staying queued', () {
      expect(
        isPermanentCancelFailure(
          const ApiError(
            code: 'invalid_request',
            message: 'reasonCode is required',
            statusCode: 400,
          ),
        ),
        isTrue,
      );
    });

    test(
      'the stand-in server requires it like openapi CancelCommand',
      () async {
        final server = InProcessMockClient();
        final api = ApiClient(client: server);
        for (final id in ['r1', 'r2']) {
          server.rides[id] = {'id': id, 'tripId': id, 'status': 'searching'};
        }
        await expectLater(
          api.post('/api/v1/rides/r1/cancel', body: {}),
          throwsA(isA<ApiError>().having((e) => e.statusCode, 'status', 400)),
        );
        // The booking stand-down cancel names one too.
        await BookingCoordinator(api: api).cancel(rideId: 'r2', key: 'k2');
        expect(server.rides['r2']!['status'], 'cancelled_by_rider');
      },
    );
  });

  test(
    'rider-u10: after a reload the demo server still knows the ride',
    () async {
      SharedPreferences.setMockInitialValues({});
      // The app's own demo transport, before and after the page reload.
      final before = ApiClient();
      expect(before.usesMockTransport, isTrue);
      final quote =
          (await before.post(
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
      final ride =
          (await before.post(
                '/api/v1/rides',
                body: {
                  'categoryId': 'economy',
                  'fare': {
                    'amountMinor': quote['totalMinor'],
                    'currency': 'SEK',
                  },
                  'paymentMethodId': 'cash',
                  'pickupLat': 59.3293,
                  'pickupLng': 18.0686,
                  'destinationLat': 59.3326,
                  'destinationLng': 18.0649,
                  'quoteId': quote['id'],
                  'quoteSignedPayload': quote['signedPayload'],
                  'quoteExpiresAt': quote['expiresAt'],
                  'quoteTotalMinor': quote['totalMinor'],
                },
              ))['ride']
              as Map;
      final id = ride['id'] as String;
      await before.post(
        '/api/v1/rides/$id/status',
        body: {'status': 'completed'},
      );

      final after = ApiClient();
      await RideFeedbackRepository(
        api: after,
      ).submit(rideId: id, rating: 5, idempotencyKey: 'fb-reload');
      final read = (await after.get('/api/v1/rides/$id'))['ride'] as Map;
      expect(read['ratingStatus'], 'submitted');
    },
  );
}
