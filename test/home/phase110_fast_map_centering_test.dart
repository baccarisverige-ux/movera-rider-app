import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:movera_rider/core/location/geocoding_repository.dart';
import 'package:movera_rider/core/location/location_repository.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/motion/motion_engine.dart';
import 'package:movera_rider/features/home/application/home_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Batch 10 Phase 110 — layered fast camera fix (native last-known →
/// app-persisted last good fix) ahead of the accurate fix. Uses the new
/// `quickCameraFix` / repository methods, so it cannot run on base; the
/// base-compatible reproduce-first file is phase110_last_good_fix_test.dart.
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
  int requests = 0;
  int cacheReads = 0;
  GeoPoint? native;
  GeoPoint? persisted;
  final List<GeoPoint> saved = [];
  Completer<Position> accurate = Completer<Position>();

  @override
  Future<bool> isLocationServiceEnabled() async => servicesOn;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async {
    requests += 1;
    return permission;
  }

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) =>
      accurate.future;

  @override
  Future<GeoPoint?> lastKnownFix() async {
    cacheReads += 1;
    return native;
  }

  @override
  Future<GeoPoint?> readLastGoodFix() async {
    cacheReads += 1;
    return persisted;
  }

  @override
  Future<void> saveLastGoodFix(GeoPoint point) async => saved.add(point);

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('native last-known fix is available before the accurate fix resolves, '
      'and the accurate fix still wins afterwards', () async {
    final location = _Location()..native = const GeoPoint(59.30, 18.00);
    final controller = _controller(location);
    addTearDown(controller.dispose);

    // Home starts both at once; the accurate fix is still pending.
    final detecting = controller.detectCurrent();
    final hint = await controller.quickCameraFix();
    expect(hint, isNotNull);
    expect(hint!.latitude, 59.30);
    expect(hint.longitude, 18.00);
    expect(controller.state, HomeLocationState.acquiringFix);

    location.accurate.complete(_position(59.3326, 18.0649));
    final detected = await detecting;
    expect(detected.target!.latitude, 59.3326);
    expect(detected.target!.longitude, 18.0649);
    expect(detected.address, 'Drottninggatan 1');
    expect(controller.state, HomeLocationState.live);
    expect(location.saved.single.latitude, 59.3326);
  });

  test('no native fix (web / fresh install): falls back to the app-persisted '
      'last good fix', () async {
    final location = _Location()..persisted = const GeoPoint(59.40, 17.95);
    final controller = _controller(location);
    addTearDown(controller.dispose);

    final hint = await controller.quickCameraFix();
    expect(hint?.latitude, 59.40);
    expect(hint?.longitude, 17.95);
  });

  test(
    'nothing cached: no hint, detection behaves exactly as before',
    () async {
      final location = _Location();
      final controller = _controller(location);
      addTearDown(controller.dispose);

      expect(await controller.quickCameraFix(), isNull);
      location.accurate.complete(_position(59.3326, 18.0649));
      final detected = await controller.detectCurrent();
      expect(detected.failure, isNull);
      expect(detected.target!.latitude, 59.3326);
    },
  );

  test('permission not yet granted / denied: no hint, no cache read, and the '
      'hint never prompts', () async {
    for (final permission in [
      LocationPermission.denied,
      LocationPermission.deniedForever,
      LocationPermission.unableToDetermine,
    ]) {
      final location = _Location()
        ..permission = permission
        ..native = const GeoPoint(59.30, 18.00)
        ..persisted = const GeoPoint(59.40, 17.95);
      final controller = _controller(location);
      expect(await controller.quickCameraFix(), isNull, reason: '$permission');
      expect(location.cacheReads, 0);
      expect(location.requests, 0, reason: 'hint must never prompt');
      controller.dispose();
    }
  });

  test('location services off: no hint', () async {
    final location = _Location()
      ..servicesOn = false
      ..native = const GeoPoint(59.30, 18.00);
    final controller = _controller(location);
    addTearDown(controller.dispose);
    expect(await controller.quickCameraFix(), isNull);
    expect(location.cacheReads, 0);
  });

  test('a hint that arrives after the accurate fix is dropped', () async {
    final location = _Location()..native = const GeoPoint(59.30, 18.00);
    final controller = _controller(location);
    addTearDown(controller.dispose);
    location.accurate.complete(_position(59.3326, 18.0649));
    await controller.detectCurrent();
    expect(await controller.quickCameraFix(), isNull);
  });

  test('the hint is camera-only: state and accuracy are untouched', () async {
    final location = _Location()..native = const GeoPoint(59.30, 18.00);
    final controller = _controller(location);
    addTearDown(controller.dispose);
    final before = controller.state;
    await controller.quickCameraFix();
    expect(controller.state, before);
    expect(controller.lastFixAccuracyMeters, isNull);
    expect(controller.markers, isEmpty);
    expect(location.saved, isEmpty, reason: 'a cached hint is never re-saved');
  });

  group('LocationRepository persistence (real SharedPreferences mock)', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('save → read round-trip', () async {
      const repo = LocationRepository();
      expect(await repo.readLastGoodFix(), isNull);
      await repo.saveLastGoodFix(const GeoPoint(59.3326, 18.0649));
      final read = await repo.readLastGoodFix();
      expect(read?.latitude, 59.3326);
      expect(read?.longitude, 18.0649);
    });

    test('corrupt or out-of-range stored data reads as null', () async {
      const repo = LocationRepository();
      SharedPreferences.setMockInitialValues({
        LocationRepository.lastGoodFixKey: 'not json',
      });
      expect(await repo.readLastGoodFix(), isNull);
      SharedPreferences.setMockInitialValues({
        LocationRepository.lastGoodFixKey: '{"lat": 123.0, "lng": 18.0}',
      });
      expect(await repo.readLastGoodFix(), isNull);
      await repo.saveLastGoodFix(const GeoPoint(double.nan, 18));
      expect(await repo.readLastGoodFix(), isNull);
    });

    test('lastKnownFix never throws when the platform cannot answer', () async {
      // No geolocator platform implementation in unit tests.
      expect(await const LocationRepository().lastKnownFix(), isNull);
    });
  });
}
