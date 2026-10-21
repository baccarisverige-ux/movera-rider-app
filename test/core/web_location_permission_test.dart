import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:movera_rider/core/location/location_repository.dart';

/// geolocator_web: the Permissions API says 'prompt' (denied) until the
/// rider answers, and requestPermission() returns deniedForever for any
/// failed getCurrentPosition (prompt dismissed, no position, timeout).
class _WebGeolocator extends GeolocatorPlatform {
  _WebGeolocator(this.afterRequest);

  /// What the Permissions API says once the request failed.
  final LocationPermission afterRequest;
  bool requested = false;

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async =>
      requested ? afterRequest : LocationPermission.denied;

  @override
  Future<LocationPermission> requestPermission() async {
    requested = true;
    return LocationPermission.deniedForever;
  }

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) =>
      Future.error(const PositionUpdateException('unavailable'));
}

/// rider-r4-21 / rider-r4-42: on the web every failed first fix was read as
/// "blocked in browser settings".
void main() {
  late GeolocatorPlatform original;
  setUp(() => original = GeolocatorPlatform.instance);
  tearDown(() => GeolocatorPlatform.instance = original);

  Future<LocationPermission> request(LocationPermission afterRequest) {
    GeolocatorPlatform.instance = _WebGeolocator(afterRequest);
    return const LocationRepository(isWeb: true).requestPermission();
  }

  test('a dismissed web prompt is not a block', () async {
    expect(
      await request(LocationPermission.denied),
      LocationPermission.denied,
    );
    expect(
      await request(LocationPermission.whileInUse),
      LocationPermission.whileInUse,
    );
    expect(
      await request(LocationPermission.deniedForever),
      LocationPermission.deniedForever,
    );
  });
}
