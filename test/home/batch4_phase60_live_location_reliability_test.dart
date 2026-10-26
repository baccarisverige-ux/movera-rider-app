import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/core/location/geocoding_repository.dart';
import 'package:movera_rider/core/location/location_repository.dart';
import 'package:movera_rider/core/motion/motion_engine.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/home/application/home_controller.dart';

Position _position({
  double latitude = 59.33,
  double longitude = 18.06,
  double heading = 90,
  double speed = 5,
}) => Position(
  latitude: latitude,
  longitude: longitude,
  timestamp: DateTime.utc(2026, 9, 24),
  accuracy: 5,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: heading,
  headingAccuracy: 5,
  speed: speed,
  speedAccuracy: 1,
);

class _Location extends LocationRepository {
  _Location({
    this.serviceEnabled = true,
    this.permission = LocationPermission.always,
    this.requestedPermission = LocationPermission.always,
    Position? current,
  }) : current = current ?? _position();

  bool serviceEnabled;
  LocationPermission permission;
  LocationPermission requestedPermission;
  Position current;
  StreamController<Position> stream = StreamController<Position>.broadcast();

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async => requestedPermission;

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async => current;

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) =>
      stream.stream;
}

class _Geocoding extends GeocodingRepository {
  @override
  Future<PlaceResult?> forward(String query) async => null;

  @override
  Future<String?> reverse(GeoPoint point) async => 'Test address';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  HomeLocationController controller(
    _Location location, {
    double? Function()? compass,
  }) => HomeLocationController(
    location: location,
    geocoding: _Geocoding(),
    motion: MotionEngine(),
    startCompass: () async => compass != null,
    readCompass: compass,
  );

  test('services disabled is explicit and never fabricates a fix', () async {
    final location = _Location(serviceEnabled: false);
    final ctl = controller(location);
    addTearDown(ctl.dispose);
    addTearDown(() => location.stream.close());

    final detected = await ctl.detectCurrent();

    expect(ctl.state, HomeLocationState.servicesDisabled);
    expect(detected.target, isNull);
    expect(detected.failure, HomeLocationFailure.servicesDisabled);
  });

  test('denied and denied-forever permissions are explicit', () async {
    for (final permission in [
      LocationPermission.denied,
      LocationPermission.deniedForever,
    ]) {
      final location = _Location(
        permission: LocationPermission.denied,
        requestedPermission: permission,
      );
      final ctl = controller(location);
      final detected = await ctl.detectCurrent();
      expect(ctl.state, HomeLocationState.permissionRequired);
      expect(detected.target, isNull);
      expect(detected.denied, isTrue);
      ctl.dispose();
      await location.stream.close();
    }
  });

  test('permission recovery acquires a real fix and becomes live', () async {
    final location = _Location(
      permission: LocationPermission.denied,
      requestedPermission: LocationPermission.denied,
    );
    final ctl = controller(location);
    addTearDown(ctl.dispose);
    addTearDown(() => location.stream.close());

    expect((await ctl.detectCurrent()).target, isNull);
    location
      ..serviceEnabled = true
      ..permission = LocationPermission.always
      ..requestedPermission = LocationPermission.always;

    final recovered = await ctl.detectCurrent();
    expect(recovered.target, const LatLng(59.33, 18.06));
    expect(ctl.state, HomeLocationState.live);
  });

  test('GPS stream failure recovers and returns live fixes', () async {
    final location = _Location();
    final ctl = controller(location);
    addTearDown(ctl.dispose);
    addTearDown(() => location.stream.close());
    final fixes = <LatLng>[];

    ctl.startTracking(
      isMounted: () => true,
      onFix: (point, _) => fixes.add(point),
    );
    location.stream.addError(StateError('temporary GPS loss'));
    await Future<void>.delayed(Duration.zero);
    expect(ctl.state, HomeLocationState.temporarilyUnavailable);

    ctl.recoverLiveLocation(
      isMounted: () => true,
      onFix: (point, _) => fixes.add(point),
    );
    expect(ctl.state, HomeLocationState.recovering);
    location.stream.add(_position(latitude: 59.4, longitude: 18.2));
    await Future<void>.delayed(Duration.zero);

    expect(ctl.state, HomeLocationState.live);
    expect(fixes.last, const LatLng(59.4, 18.2));
  });

  test('compass wins over GPS course while available', () async {
    var compass = 180.0;
    final location = _Location(current: _position(heading: 40));
    final ctl = controller(location, compass: () => compass);
    addTearDown(ctl.dispose);
    addTearDown(() => location.stream.close());

    await ctl.startHeading(isMounted: () => true, onHeading: (_) {});
    ctl.pollHeading();
    expect(ctl.hasCompassHeading, isTrue);
    final compassHeading = ctl.heading;

    ctl.startTracking(isMounted: () => true, onFix: (_, __) {});
    location.stream.add(_position(heading: 20));
    await Future<void>.delayed(Duration.zero);
    expect(ctl.heading, compassHeading);
  });

  test('GPS course is fallback and no source stays neutral', () async {
    final location = _Location(current: _position(heading: 75));
    final ctl = controller(location);
    addTearDown(ctl.dispose);
    addTearDown(() => location.stream.close());

    ctl.startTracking(isMounted: () => true, onFix: (_, __) {});
    location.stream.add(_position(heading: 75));
    await Future<void>.delayed(Duration.zero);
    expect(ctl.hasCompassHeading, isFalse);
    expect(ctl.heading, 75);

    ctl.heading = 0;
    location.stream.add(_position(heading: double.nan, speed: 0));
    await Future<void>.delayed(Duration.zero);
    expect(ctl.heading, 0);
  });
}
