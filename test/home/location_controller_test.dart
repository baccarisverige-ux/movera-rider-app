import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/core/location/app_geocoding.dart';
import 'package:movera_rider/core/location/location_repository.dart';
import 'package:movera_rider/core/motion/motion_engine.dart';
import 'package:movera_rider/features/home/application/home_controller.dart';
import 'package:movera_rider/core/location/geocoding_repository.dart';
import 'package:movera_rider/core/maps/geo_point.dart';

class _SlowGeo extends AppGeocoding {
  Duration delay = const Duration(milliseconds: 40);
  String resolved = 'Resolved address';

  @override
  Future<PlaceResult?> forward(String address) async {
    await Future<void>.delayed(delay);
    return PlaceResult(point: const GeoPoint(59.33, 18.06), address: resolved);
  }
}

class _DeniedLocation extends LocationRepository {
  int permissionRequests = 0;

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.denied;

  @override
  Future<LocationPermission> requestPermission() async {
    permissionRequests += 1;
    return LocationPermission.denied;
  }

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) {
    throw StateError('GPS must not be requested after permission denial');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  HomeLocationController controllerOf(
    _SlowGeo geo, {
    LocationRepository? location,
  }) {
    return HomeLocationController(
      location: location ?? LocationRepository(),
      geocoding: geo,
      motion: MotionEngine(),
    );
  }

  test('overlay sets live on the location controller', () {
    final ctl = controllerOf(_SlowGeo());
    ctl.clearOverlays();
    expect(ctl.markers, isEmpty);
    expect(ctl.locationCircles, isEmpty);
    expect(ctl.locationDirection, isEmpty);
    ctl.dispose();
  });

  test(
    'permission denied during detection returns a usable no-GPS state',
    () async {
      final location = _DeniedLocation();
      final ctl = controllerOf(_SlowGeo(), location: location);

      final detected = await ctl.detectCurrent();

      expect(location.permissionRequests, 1);
      expect(detected.denied, isTrue);
      expect(detected.target, isNull);
      expect(detected.address, locationOffPickupLabel);
      expect(detected.heading, 0);
      ctl.dispose();
    },
  );

  test('geocode result after dispose is ignored', () async {
    final geo = _SlowGeo();
    final ctl = controllerOf(geo);
    final pending = ctl.normaliseAddress('Stockholm Central Station');
    ctl.dispose();
    expect(await pending, 'Stockholm Central Station');
  });

  test('later geocode generation wins when the first finishes late', () async {
    final geo = _SlowGeo()..delay = const Duration(milliseconds: 50);
    final ctl = controllerOf(geo);
    final first = ctl.geocodeLatLng('Destination A');
    geo.delay = Duration.zero;
    geo.resolved = 'Destination B';
    final second = ctl.geocodeLatLng('Destination B');
    final late = await first;
    final latest = await second;
    expect(late, isNull);
    expect(latest, const LatLng(59.33, 18.06));
    ctl.dispose();
  });
}
