import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/features/booking/application/booking_controller.dart';
import 'package:movera_rider/features/booking/application/booking_coordinator.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/active_trip_repository.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ActiveTrip implements ActiveTripRepository {
  _ActiveTrip(this.trip);
  final RideSnapshot? trip;
  int calls = 0;

  @override
  Future<RideSnapshot?> fetchActive() async {
    calls += 1;
    return trip;
  }
}

/// RC-04 / RC-09: a booking retried after a failure that may have created
/// the ride resends the first request (same key, same body), and is not
/// reported as refused before the server's active trip was checked.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RideSnapshotStore.epoch = 0;
    FindingDriverController.active = null;
    AppScope.instance.ride
      ..rideId = null
      ..status = RideStatus.idle;
  });

  tearDown(() {
    AppScope.instance.ride.restoreFromBackend(RideStatus.idle);
    AppScope.instance.ride.rideId = null;
  });

  ({ApiClient api, List<String?> keys, List<String> bodies}) unavailable() {
    final keys = <String?>[];
    final bodies = <String>[];
    final api = ApiClient(
      client: MockClient((req) async {
        keys.add(req.headers['Idempotency-Key']);
        bodies.add(req.body);
        return http.Response(jsonEncode({'code': 'UNAVAILABLE'}), 503);
      }),
      env: AppEnv.current,
    );
    return (api: api, keys: keys, bodies: bodies);
  }

  Future<String> attempt(
    BookingCoordinator booking,
    String quoteId,
    double pickupLat,
  ) => booking.submitFinding(
    pickupAddress: 'A',
    destinationAddress: 'B',
    pickupLat: pickupLat,
    pickupLng: 18.0686,
    destinationLat: 59.34,
    destinationLng: 18.07,
    rideType: 'standard',
    price: 120,
    paymentMethod: 'card',
    quoteId: quoteId,
    quoteSignedPayload: 'sig-$quoteId',
    quoteExpiresAt: DateTime.now().add(const Duration(minutes: 5)),
    quoteTotalMinor: 12000,
  );

  test('RC-04: a retry after a 503 resends the first body under the key',
      () async {
    final t = unavailable();
    final booking = BookingCoordinator(
      api: t.api,
      activeTrips: _ActiveTrip(null),
    );
    await expectLater(attempt(booking, 'q1', 59.32930), throwsA(isA<ApiError>()));
    // Same trip, re-quoted after the failure; pin nudged 3 m.
    await expectLater(attempt(booking, 'q2', 59.32932), throwsA(isA<ApiError>()));
    expect(t.keys.toSet(), hasLength(1));
    expect(t.bodies.toSet(), hasLength(1));
    expect(jsonDecode(t.bodies.last)['quoteId'], 'q1');
  });

  test('RC-09: before failing, a maybe-created booking is retried once and '
      'the active trip is checked', () async {
    final t = unavailable();
    final trips = _ActiveTrip(null);
    final booking = BookingCoordinator(api: t.api, activeTrips: trips);
    Object? failure;
    try {
      await attempt(booking, 'q1', 59.3293);
    } catch (error) {
      failure = error;
    }
    expect(t.keys, hasLength(2));
    expect(trips.calls, 1);
    expect(BookingController.mayHaveBooked(failure!), isTrue);
  });

  test('RC-09: the live trip the server holds for this booking is adopted',
      () async {
    final t = unavailable();
    final trips = _ActiveTrip(RideSnapshot(
      status: RideStatus.findingDriver,
      savedAt: DateTime.now(),
      pickupAddress: 'A',
      destinationAddress: 'B',
      pickupLat: 59.3293,
      pickupLng: 18.0686,
      destinationLat: 59.34,
      destinationLng: 18.07,
      rideType: 'standard',
      price: 120,
      paymentMethod: 'card',
      rideId: 'srv-1',
      categoryId: 'standard',
    ));
    final booking = BookingCoordinator(api: t.api, activeTrips: trips);
    expect(await attempt(booking, 'q1', 59.3293), 'srv-1');
    expect(AppScope.instance.ride.rideId, 'srv-1');
    expect((await RideSnapshotStore.read())?.rideId, 'srv-1');
  });

  test('a refusal is not "maybe booked"', () {
    expect(
      BookingController.mayHaveBooked(
        const ApiError(code: 'QUOTE_EXPIRED', message: 'x', statusCode: 409),
      ),
      isFalse,
    );
    expect(BookingController.mayHaveBooked(StateError('stale quote')), isFalse);
  });
}
