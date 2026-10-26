import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:movera_rider/core/location/geocoding_repository.dart';
import 'package:movera_rider/core/location/location_repository.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/motion/motion_engine.dart';
import 'package:movera_rider/features/home/application/home_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Batch 10 Phase 110 — the app remembers its last good high-accuracy fix so
/// the next cold start can centre the map camera at once (web included).
///
/// Only pre-existing APIs are used (detectCurrent / latestFix + the prefs
/// key), so this file also runs on the base commit. Behavioural only.
const _key = 'movera.location.last_good_fix.v1';

Position _position(double lat, double lng) => Position(
  latitude: lat,
  longitude: lng,
  timestamp: DateTime.utc(2026, 9, 27),
  accuracy: 5,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

class _Location extends LocationRepository {
  bool servicesOn = true;
  LocationPermission permission = LocationPermission.whileInUse;
  LocationPermission afterRequest = LocationPermission.whileInUse;
  int requests = 0;
  Object? fail;
  Position current = _position(59.3326, 18.0649);

  @override
  Future<bool> isLocationServiceEnabled() async => servicesOn;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async {
    requests += 1;
    return afterRequest;
  }

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) {
    final error = fail;
    if (error != null) return Future.error(error);
    return Future.value(current);
  }

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) =>
      const Stream.empty();
}

class _Geocoding extends GeocodingRepository {
  @override
  Future<PlaceResult?> forward(String query) async => null;

  @override
  Future<String?> reverse(GeoPoint point) async => 'Drottninggatan 1';
}

HomeLocationController _controller(_Location location) =>
    HomeLocationController(
      location: location,
      geocoding: _Geocoding(),
      motion: MotionEngine(),
      startCompass: () async => false,
      readCompass: () => null,
      stopCompass: () {},
    );

Future<Map<String, dynamic>?> _saved() async {
  await pumpEventQueue();
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_key);
  return raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'a successful high-accuracy detection is remembered for next start',
    () async {
      final location = _Location();
      final controller = _controller(location);
      addTearDown(controller.dispose);

      final detected = await controller.detectCurrent();
      expect(detected.failure, isNull);

      final saved = await _saved();
      expect(saved, isNotNull, reason: 'last good fix was not persisted');
      expect(saved!['lat'], closeTo(59.3326, 1e-9));
      expect(saved['lng'], closeTo(18.0649, 1e-9));
    },
  );

  test(
    'a later successful latestFix (recenter) refreshes the saved fix',
    () async {
      final location = _Location();
      final controller = _controller(location);
      addTearDown(controller.dispose);
      await controller.detectCurrent();

      location.current = _position(59.35, 18.10);
      await controller.latestFix();

      final saved = await _saved();
      expect(saved, isNotNull);
      expect(saved!['lat'], closeTo(59.35, 1e-9));
      expect(saved['lng'], closeTo(18.10, 1e-9));
    },
  );

  test(
    'a failed detection saves nothing and fails exactly as before',
    () async {
      final location = _Location()..fail = TimeoutException('no fix');
      final controller = _controller(location);
      addTearDown(controller.dispose);

      final detected = await controller.detectCurrent();
      expect(detected.failure, HomeLocationFailure.unavailable);
      expect(detected.address, locationOffPickupLabel);
      expect(controller.state, HomeLocationState.temporarilyUnavailable);
      expect(await _saved(), isNull);
    },
  );

  test(
    'denied permission / services off: same outcome as before, nothing saved',
    () async {
      final denied = _Location()
        ..permission = LocationPermission.denied
        ..afterRequest = LocationPermission.denied;
      final c1 = _controller(denied);
      addTearDown(c1.dispose);
      final r1 = await c1.detectCurrent();
      expect(r1.failure, HomeLocationFailure.permissionDenied);
      expect(denied.requests, 1);
      expect(c1.state, HomeLocationState.permissionRequired);

      final off = _Location()..servicesOn = false;
      final c2 = _controller(off);
      addTearDown(c2.dispose);
      final r2 = await c2.detectCurrent();
      expect(r2.failure, HomeLocationFailure.servicesDisabled);
      expect(off.requests, 0);

      expect(await _saved(), isNull);
    },
  );
}
