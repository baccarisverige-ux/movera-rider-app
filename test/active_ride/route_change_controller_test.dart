import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/location/geocoding_repository.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/active_ride/application/route_change_controller.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../mock_fare.dart';

class _Geo implements GeocodingRepository {
  _Geo(this.known);
  final Map<String, GeoPoint> known;
  final List<String> asked = [];

  @override
  Future<PlaceResult?> forward(String query) async {
    asked.add(query);
    final point = known[query];
    return point == null ? null : PlaceResult(address: query, point: point);
  }

  @override
  Future<String?> reverse(GeoPoint point) async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const pickup = GeoPoint(59.3326, 18.0649); // Sergels torg
  const drop = GeoPoint(59.3426, 18.0498); // Odenplan
  const stopAt = GeoPoint(59.3365, 18.0586); // Hötorget, on the way
  const farAway = GeoPoint(59.4000, 18.2000);

  RideSnapshot ride({RideStatus status = RideStatus.findingDriver}) =>
      RideSnapshot(
        status: status,
        savedAt: DateTime(2026, 10, 13),
        pickupAddress: 'Sergels torg 1',
        destinationAddress: 'Odenplan 2',
        pickupLat: pickup.latitude,
        pickupLng: pickup.longitude,
        destinationLat: drop.latitude,
        destinationLng: drop.longitude,
        rideType: 'Movera',
        price: 200,
        paymentMethod: 'Apple Pay',
        rideId: 'ride-route-1',
      );

  InProcessMockClient backend({String status = 'findingDriver'}) {
    final mock = InProcessMockClient();
    mock.rides['ride-route-1'] = {
      'id': 'ride-route-1',
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

  RouteChangeController controller(InProcessMockClient mock, _Geo geo) =>
      RouteChangeController(api: ApiClient(client: mock), geocoding: geo);

  test('a stop on the way costs the stop fee and the extra kilometres', () async {
    final mock = backend();
    final geo = _Geo({'Hötorget': stopAt});
    final quote = await controller(mock, geo).preview(
      ride: ride(),
      destinationAddress: 'Odenplan 2',
      stops: const ['Hötorget'],
    );
    expect(geo.asked, ['Hötorget']);
    expect(quote.oldPriceKr, 200);
    expect(quote.stops.single.address, 'Hötorget');
    // 25 kr for the stop plus a little detour: never cheaper than before.
    expect(quote.newPriceKr, greaterThanOrEqualTo(225));
    expect(quote.newPriceKr, lessThan(260));
    expect(quote.differenceKr, quote.newPriceKr - 200);
    // A preview does not touch the ride.
    expect(mock.rides['ride-route-1']!['stops'], isEmpty);
    expect(mockFareKr(mock.rides['ride-route-1']!), 200.0);
  });

  test('a far destination costs more; applying tells the driver and saves', () async {
    final mock = backend(status: 'driverArriving');
    final geo = _Geo({'Arlanda': farAway});
    final changes = controller(mock, geo);
    final quote = await changes.preview(
      ride: ride(status: RideStatus.driverArriving),
      destinationAddress: 'Arlanda',
    );
    expect(quote.newPriceKr, greaterThan(300));

    final updated = await changes.apply(
      ride: ride(status: RideStatus.driverArriving),
      quote: quote,
    );
    expect(updated.destinationAddress, 'Arlanda');
    expect(updated.destinationLat, farAway.latitude);
    expect(updated.price, quote.newPriceKr);
    expect(updated.status, RideStatus.driverArriving);

    final server = mock.rides['ride-route-1']!;
    expect(server['destinationAddress'], 'Arlanda');
    expect(mockFareKr(server), quote.newPriceKr);
    expect(server['version'], 4);
    expect(server['driverNotifiedAt'], isNotNull);
    expect((server['routeChanges'] as List).length, 1);

    final saved = await RideSnapshotStore.read();
    expect(saved?.destinationAddress, 'Arlanda');
    expect(saved?.price, quote.newPriceKr);
  });

  test('a shorter route gives money back, never below half the booked price',
      () async {
    final mock = backend();
    final geo = _Geo({'Next door': const GeoPoint(59.3330, 18.0655)});
    final quote = await controller(mock, geo).preview(
      ride: ride(),
      destinationAddress: 'Next door',
    );
    expect(quote.newPriceKr, lessThan(200));
    expect(quote.newPriceKr, greaterThanOrEqualTo(100));
    expect(quote.differenceKr, isNegative);
  });

  test('the pickup is locked once the driver is there', () async {
    final mock = backend(status: 'driverWaiting');
    final geo = _Geo({'Somewhere else': farAway});
    expect(
      () => controller(mock, geo).preview(
        ride: ride(status: RideStatus.driverWaiting),
        pickupAddress: 'Somewhere else',
        destinationAddress: 'Odenplan 2',
      ),
      throwsA(
        isA<RouteChangeException>().having(
          (e) => e.failure,
          'failure',
          RouteChangeFailure.pickupLocked,
        ),
      ),
    );
  });

  test('a finished ride cannot change', () async {
    final mock = backend(status: 'tripCompleted');
    final geo = _Geo({'Arlanda': farAway});
    expect(
      () => controller(mock, geo).preview(
        ride: ride(status: RideStatus.tripCompleted),
        destinationAddress: 'Arlanda',
      ),
      throwsA(
        isA<RouteChangeException>().having(
          (e) => e.failure,
          'failure',
          RouteChangeFailure.rideFinished,
        ),
      ),
    );
  });

  test('an unknown address is reported, not sent', () async {
    final mock = backend();
    final geo = _Geo({});
    expect(
      () => controller(mock, geo).preview(
        ride: ride(),
        destinationAddress: 'Nowhere street 0',
      ),
      throwsA(
        isA<RouteChangeException>().having(
          (e) => e.failure,
          'failure',
          RouteChangeFailure.addressNotFound,
        ),
      ),
    );
  });

  test('known stops keep their points without a new lookup', () async {
    final mock = backend();
    final geo = _Geo({});
    final current = ride().copyWith(
      stops: const [
        RouteStop(address: 'Hötorget', latitude: 59.3365, longitude: 18.0586),
      ],
    );
    final quote = await controller(mock, geo).preview(
      ride: current,
      destinationAddress: 'Odenplan 2',
      stops: const ['Hötorget'],
    );
    expect(geo.asked, isEmpty);
    expect(quote.stops.single.latitude, 59.3365);
  });
}
