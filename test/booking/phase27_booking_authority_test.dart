import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/api/mutation_attempt.dart';
import 'package:movera_rider/features/booking/application/booking_coordinator.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/ride_booking/data/api_quote_repository.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _JsonClient extends http.BaseClient {
  _JsonClient(this.payload);
  final Map<String, dynamic> payload;
  int sends = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sends += 1;
    final bytes = utf8.encode(jsonEncode(payload));
    return http.StreamedResponse(
      Stream<List<int>>.value(bytes),
      200,
      headers: const {'content-type': 'application/json'},
      contentLength: bytes.length,
    );
  }
}

void resetRide() {
  FindingDriverController.active = null;
  final ride = AppScope.instance.ride;
  ride
    ..rideId = null
    ..authoritativeVersion = null
    ..authoritativeUpdatedAt = null
    ..backendReconcile(RideStatus.idle);
}

Future<void> mainSetup() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await RideSnapshotStore.clear();
  resetRide();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(mainSetup);
  tearDown(() {
    FindingDriverController.active = null;
  });

  test('MutationAttempt reuses failed intent and rotates after success', () {
    final attempt = MutationAttempt('ride-pickup');

    final first = attempt.keyFor('same-intent');
    final retry = attempt.keyFor('same-intent');
    expect(retry, first);

    final changed = attempt.keyFor('changed-intent');
    expect(changed, isNot(first));

    attempt.succeeded('changed-intent');
    final later = attempt.keyFor('changed-intent');
    expect(later, isNot(changed));
  });

  test(
    'booking rejects response with missing trip id instead of creating "null"',
    () async {
      final transport = _JsonClient(<String, dynamic>{
        'ride': <String, dynamic>{'status': 'findingDriver'},
      });
      final booking = BookingCoordinator(api: ApiClient(client: transport));

      await expectLater(
        booking.submitFinding(
          pickupAddress: 'A',
          destinationAddress: 'B',
          pickupLat: 59.3,
          pickupLng: 18.0,
          destinationLat: 59.4,
          destinationLng: 18.1,
          rideType: 'economy',
          price: 259,
          paymentMethod: 'apple',
          quoteId: 'q-1',
          quoteSignedPayload: 'signed',
          quoteExpiresAt: DateTime.now().add(const Duration(minutes: 2)),
          quoteTotalMinor: 25900,
        ),
        throwsA(isA<FormatException>()),
      );

      expect(AppScope.instance.ride.rideId, isNull);
      expect(AppScope.instance.ride.rideId, isNot('null'));
    },
  );

  test(
    'expired quote is rejected before any booking request is sent',
    () async {
      final transport = _JsonClient(<String, dynamic>{});
      final booking = BookingCoordinator(api: ApiClient(client: transport));

      await expectLater(
        booking.submitFinding(
          pickupAddress: 'A',
          destinationAddress: 'B',
          pickupLat: 59.3,
          pickupLng: 18.0,
          destinationLat: 59.4,
          destinationLng: 18.1,
          rideType: 'economy',
          price: 259,
          paymentMethod: 'apple',
          quoteId: 'q-expired',
          quoteSignedPayload: 'signed',
          quoteExpiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
          quoteTotalMinor: 25900,
        ),
        throwsA(isA<StateError>()),
      );

      expect(transport.sends, 0);
    },
  );

  test(
    'Book Now stores the exact authoritative quote binding on the trip',
    () async {
      final transport = InProcessMockClient();
      final api = ApiClient(client: transport);
      final quote = await ApiQuoteRepository(api: api).quote(
        rideType: 'economy',
        distanceMeters: 3000,
        pickup: 'A',
        destination: 'B',
      );
      final booking = BookingCoordinator(api: api);

      final tripId = await booking.submitFinding(
        pickupAddress: 'A',
        destinationAddress: 'B',
        pickupLat: 59.3,
        pickupLng: 18.0,
        destinationLat: 59.4,
        destinationLng: 18.1,
        rideType: 'economy',
        price: quote.totalMinor / 100,
        paymentMethod: 'apple',
        quoteId: quote.id,
        quoteSignedPayload: quote.signedPayload!,
        quoteExpiresAt: quote.expiresAt,
        quoteTotalMinor: quote.totalMinor,
      );

      final response = await api.get('/api/v1/rides/$tripId');
      final ride = Map<String, dynamic>.from(response['ride'] as Map);

      expect(ride['id'], tripId);
      expect(ride['quoteId'], quote.id);
      expect(ride['quoteSignedPayload'], quote.signedPayload);
      expect(ride['quoteTotalMinor'], quote.totalMinor);
      expect(ride['quoteExpiresAt'], quote.expiresAt.toUtc().toIso8601String());

      final snapshot = await RideSnapshotStore.read();
      expect(snapshot?.rideId, tripId);
    },
  );

  test(
    'mock backend rejects an on-demand booking without a quote binding',
    () async {
      final api = ApiClient(client: InProcessMockClient());

      await expectLater(
        api.post(
          '/api/v1/rides',
          body: <String, dynamic>{
            'pickupAddress': 'A',
            'destinationAddress': 'B',
            'pickupLat': 59.3,
            'pickupLng': 18.0,
            'destinationLat': 59.4,
            'destinationLng': 18.1,
            'categoryId': 'economy',
            'price': 259,
            'paymentMethodId': 'apple',
          },
        ),
        throwsA(isA<Object>()),
      );
    },
  );
}
