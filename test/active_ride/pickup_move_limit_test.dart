import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/config/rider_app_config.dart';
import 'package:movera_rider/core/location/geocoding_repository.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/active_ride/application/route_change_controller.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Geo implements GeocodingRepository {
  _Geo(this.known);
  final Map<String, GeoPoint> known;

  @override
  Future<PlaceResult?> forward(String query) async {
    final point = known[query];
    return point == null ? null : PlaceResult(address: query, point: point);
  }

  @override
  Future<String?> reverse(GeoPoint point) async => null;
}

/// Q40: once a driver accepted, the pickup moves up to 500 m; further is
/// cancel and rebook. The driver is told when it moved.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const pickup = GeoPoint(59.3326, 18.0649);
  const drop = GeoPoint(59.3426, 18.0498);
  // About 300 m and 800 m north of the pickup.
  const near = GeoPoint(59.3353, 18.0649);
  const far = GeoPoint(59.3398, 18.0649);
  final limit = RiderAppConfig.defaultMaxPickupMoveAfterAcceptMeters;

  RideSnapshot ride() => RideSnapshot(
    status: RideStatus.driverArriving,
    savedAt: DateTime(2026, 10, 20),
    pickupAddress: 'Sergels torg 1',
    destinationAddress: 'Odenplan 2',
    pickupLat: pickup.latitude,
    pickupLng: pickup.longitude,
    destinationLat: drop.latitude,
    destinationLng: drop.longitude,
    rideType: 'Movera',
    price: 200,
    paymentMethod: 'Apple Pay',
    rideId: 'ride-move-1',
  );

  InProcessMockClient backend({String status = 'driverArriving'}) {
    final mock = InProcessMockClient();
    mock.rides['ride-move-1'] = {
      'id': 'ride-move-1',
      'status': status,
      'pickupAddress': 'Sergels torg 1',
      'pickupLat': pickup.latitude,
      'pickupLng': pickup.longitude,
      'destinationAddress': 'Odenplan 2',
      'destinationLat': drop.latitude,
      'destinationLng': drop.longitude,
      'price': 200.0,
      'bookedPrice': 200.0,
      'bookedKm': 1.4,
      'stops': <Map<String, dynamic>>[],
      'version': 3,
    };
    return mock;
  }

  test('the default limit is 500 m', () => expect(limit, 500));

  test('a pickup moved more than the limit after accept is refused', () async {
    final changes = RouteChangeController(
      api: ApiClient(client: backend()),
      geocoding: _Geo({'Far corner': far}),
    );
    await expectLater(
      changes.preview(
        ride: ride(),
        pickupAddress: 'Far corner',
        destinationAddress: 'Odenplan 2',
        maxPickupMoveMeters: limit,
      ),
      throwsA(
        isA<RouteChangeException>()
            .having((e) => e.failure, 'failure', RouteChangeFailure.pickupTooFar)
            .having((e) => e.message, 'message', contains('cancel this ride')),
      ),
    );
  });

  test('a short move is priced, applied and the driver is told', () async {
    final mock = backend();
    final changes = RouteChangeController(
      api: ApiClient(client: mock),
      geocoding: _Geo({'Near corner': near}),
    );
    final quote = await changes.preview(
      ride: ride(),
      pickupAddress: 'Near corner',
      destinationAddress: 'Odenplan 2',
      maxPickupMoveMeters: limit,
    );
    await changes.apply(ride: ride(), quote: quote);
    final server = mock.rides['ride-move-1']!;
    expect(server['pickupAddress'], 'Near corner');
    final notice = (server['driverNotices'] as List).single as Map;
    expect(notice['kind'], 'pickup_moved');
    expect(notice['meters'], inInclusiveRange(250, 350));
  });

  test('the demo server refuses a long move after accept on its own', () async {
    final api = ApiClient(client: backend());
    await expectLater(
      api.patch(
        '/api/v1/rides/ride-move-1',
        body: {
          'routeChange': true,
          'pickupAddress': 'Far corner',
          'pickupLat': far.latitude,
          'pickupLng': far.longitude,
          'destinationAddress': 'Odenplan 2',
          'destinationLat': drop.latitude,
          'destinationLng': drop.longitude,
          'stops': const <Object>[],
        },
      ),
      throwsA(
        isA<ApiError>().having((e) => e.detail, 'detail', 'pickup_too_far'),
      ),
    );
  });

  test('before a driver accepted there is no such limit', () async {
    final changes = RouteChangeController(
      api: ApiClient(client: backend(status: 'findingDriver')),
      geocoding: _Geo({'Far corner': far}),
    );
    final quote = await changes.preview(
      ride: ride(),
      pickupAddress: 'Far corner',
      destinationAddress: 'Odenplan 2',
    );
    expect(quote.pickupAddress, 'Far corner');
  });
}
