import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:movera_rider/core/location/geocoding_repository.dart';
import 'package:movera_rider/core/location/location_repository.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/motion/motion_engine.dart';
import 'package:movera_rider/features/home/application/home_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Owner, live test 2026-10-26 (N7): right after sign-in Home showed a wrong
/// street for a second, then the right one. The phone's first fix is often
/// a cached or network position hundreds of metres off; Home named it with
/// the reverse geocoder and relabelled when the live stream's first good fix
/// landed more than 75 m away. A fix too uncertain to name a street is not
/// named: the pickup stays "Current location" until a good fix lands.
Position _position(double lat, double lng, {required double accuracy}) =>
    Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime.utc(2026, 10, 26),
      accuracy: accuracy,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

class _Location extends LocationRepository {
  _Location(this.fix);
  final Position fix;

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.whileInUse;

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) =>
      Future.value(fix);

  @override
  Future<GeoPoint?> lastKnownFix() async => null;

  @override
  Future<GeoPoint?> readLastGoodFix() async => null;

  @override
  Future<void> saveLastGoodFix(GeoPoint point) async {}

  @override
  Future<bool> isApproximateOnly() async => false;

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) =>
      const Stream.empty();
}

class _Geocoding extends GeocodingRepository {
  int reverseCalls = 0;

  @override
  Future<PlaceResult?> forward(String query) async => null;

  @override
  Future<String?> reverse(GeoPoint point) async {
    reverseCalls += 1;
    return 'Klockarvägen 37';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  HomeLocationController controller(Position fix, _Geocoding geocoding) =>
      HomeLocationController(
        location: _Location(fix),
        geocoding: geocoding,
        motion: MotionEngine(),
        startCompass: () async => false,
        readCompass: () => null,
        stopCompass: () {},
      );

  test('a coarse first fix is not named: "Current location" and no reverse '
      'geocode, while the point still serves the puck', () async {
    final geocoding = _Geocoding();
    final ctl = controller(
      _position(59.1955, 17.6253, accuracy: 900),
      geocoding,
    );
    addTearDown(ctl.dispose);
    DetectedLocation? located;

    final detected = await ctl.detectCurrent(onLocated: (fix) => located = fix);

    expect(geocoding.reverseCalls, 0);
    expect(detected.address, 'Current location');
    expect(isPlaceholderPickupLabel(detected.address), isTrue);
    expect(detected.target!.latitude, 59.1955);
    expect(located?.target?.latitude, 59.1955);
    expect(ctl.lastFixAccuracyMeters, 900);
    expect(ctl.state, HomeLocationState.live);
  });

  test('a fix good enough to name a street is named as before', () async {
    final geocoding = _Geocoding();
    final ctl = controller(
      _position(59.1955, 17.6253, accuracy: 20),
      geocoding,
    );
    addTearDown(ctl.dispose);

    final detected = await ctl.detectCurrent();

    expect(geocoding.reverseCalls, 1);
    expect(detected.address, 'Klockarvägen 37');
  });

  test('the naming threshold', () {
    expect(HomeLocationController.nameable(null), isTrue);
    expect(HomeLocationController.nameable(20), isTrue);
    expect(HomeLocationController.nameable(150), isTrue);
    expect(HomeLocationController.nameable(151), isFalse);
    expect(HomeLocationController.nameable(double.nan), isTrue);
  });
}
