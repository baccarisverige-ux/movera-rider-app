import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/location/app_geocoding.dart';
import 'package:movera_rider/core/location/geocoding_repository.dart';
import 'package:movera_rider/core/location/location_repository.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/motion/motion_engine.dart';
import 'package:movera_rider/features/home/application/home_controller.dart';

void main() {
  test(
    'Pages mock implements forward and reverse geocoding contracts',
    () async {
      final api = ApiClient(client: InProcessMockClient());
      final geocoding = AppGeocoding(api: api);

      final place = await geocoding.forward('Stockholm Central');
      expect(place, isNotNull);
      expect(place!.address, 'Stockholm Central');

      final address = await geocoding.reverse(const GeoPoint(59.33, 18.07));
      expect(address, 'Current location');
    },
  );

  test('GPS fix survives reverse-geocoder failure', () async {
    final controller = HomeLocationController(
      location: _Location(),
      geocoding: _FailingGeocoding(),
      motion: MotionEngine(),
      startCompass: () async => false,
      readCompass: () => null,
      stopCompass: () {},
    );

    final result = await controller.detectCurrent();
    expect(result.target, isNotNull);
    expect(result.target!.latitude, closeTo(59.35, 0.000001));
    expect(result.target!.longitude, closeTo(18.05, 0.000001));
    expect(result.address, 'Current location');
    expect(result.failure, isNull);
    expect(controller.state, HomeLocationState.live);
    controller.dispose();
  });
}

class _FailingGeocoding implements GeocodingRepository {
  @override
  Future<PlaceResult?> forward(String query) async => null;

  @override
  Future<String?> reverse(GeoPoint point) async => throw StateError('offline');
}

class _Location implements LocationRepository {
  @override
  bool get isWeb => false;

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.always;

  @override
  Future<LocationPermission> requestPermission() async =>
      LocationPermission.always;

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async => Position(
    latitude: 59.35,
    longitude: 18.05,
    timestamp: DateTime.now(),
    accuracy: 4,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 12,
    headingAccuracy: 2,
    speed: 0,
    speedAccuracy: 0,
  );

  @override
  Future<GeoPoint?> lastKnownFix() async => null;

  @override
  Future<bool> isApproximateOnly() async => false;

  @override
  Future<bool> requestPreciseLocation() async => true;

  @override
  Future<GeoPoint?> readLastGoodFix() async => null;

  @override
  Future<void> saveLastGoodFix(GeoPoint point) async {}

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) =>
      const Stream.empty();

  @override
  double distanceBetween(
    double startLatitude,
    double startLongitude,
    double endLatitude,
    double endLongitude,
  ) => 0;
}
