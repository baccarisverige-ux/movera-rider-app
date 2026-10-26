import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/contracts/cancel_reasons.dart';

/// Owner decision 6 (contract v0.4.4 §3 "After-cancel reason") on the
/// stand-in server: `POST /trips/{tripId}/cancel-reason` (rider-u19).
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
    final ride =
        (await api.post(
              '/api/v1/rides',
              body: {
                'categoryId': 'economy',
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
            ))['ride']
            as Map;
    return ride['id'] as String;
  }

  Future<Map> reason(
    String id,
    Map<String, Object> body, {
    String? key,
  }) async =>
      (await api.post(
            '/api/v1/trips/$id/cancel-reason',
            body: body,
            idempotencyKey: key,
          ))['ride']
          as Map;

  Future<ApiError> refused(Future<Object?> call) async {
    try {
      await call;
    } on ApiError catch (error) {
      return error;
    }
    fail('expected an ApiError');
  }

  test(
    'sets the reason of a cancel-first once; nothing else changes',
    () async {
      final id = await book();
      await api.post('/api/v1/rides/$id/status', body: {'status': 'accepted'});
      final cancelled = Map<String, dynamic>.from(
        (await api.post(
              '/api/v1/rides/$id/cancel',
              body: CancelReasonCodes.riderCancelBody(null),
            ))['ride']
            as Map,
      );
      final before = Map<String, dynamic>.from(
        cancelled['cancellation'] as Map,
      );

      const body = {'reasonCode': 'wait_too_long', 'note': 'Too slow'};
      final told = await reason(id, body, key: 'reason-key-0000000001');
      expect(told['cancellation'], {
        ...before,
        'reasonCode': 'wait_too_long',
        'note': 'Too slow',
      });
      for (final field in [
        'status',
        'version',
        'sequence',
        'updatedAt',
        'fare',
      ]) {
        expect(told[field], cancelled[field], reason: field);
      }
      // Same key, same body: the first answer again (idempotent).
      expect(await reason(id, body, key: 'reason-key-0000000001'), told);
      // The reason is told: a new one is 409 invalid_transition.
      final again = await refused(reason(id, {'reasonCode': 'plans_changed'}));
      expect(again.code, 'invalid_transition');
      expect(server.rides[id]!['cancellation']['reasonCode'], 'wait_too_long');
    },
  );

  test(
    'a live trip is 409, a non-rider code 400, an unknown trip 404',
    () async {
      final id = await book();
      final live = await refused(reason(id, {'reasonCode': 'plans_changed'}));
      expect(live.code, 'invalid_transition');
      expect(live.projection?['status'], isNot('cancelled_by_rider'));

      await api.post(
        '/api/v1/rides/$id/cancel',
        body: CancelReasonCodes.riderCancelBody(null),
      );
      final driverCode = await refused(
        reason(id, {'reasonCode': 'rider_not_at_pickup'}),
      );
      expect(driverCode.statusCode, 400);
      expect(driverCode.code, 'invalid_request');
      expect(
        server.rides[id]!['cancellation']['reasonCode'],
        CancelReasonCodes.unspecified,
      );

      final unknown = await refused(
        reason('nope', {'reasonCode': 'plans_changed'}),
      );
      expect(unknown.statusCode, 404);
    },
  );
}
