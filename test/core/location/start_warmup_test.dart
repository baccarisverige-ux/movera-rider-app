import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/location/app_geocoding.dart';
import 'package:movera_rider/core/location/location_repository.dart';
import 'package:movera_rider/core/location/start_warmup.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/motion/motion_engine.dart';
import 'package:movera_rider/features/home/application/home_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Owner job "Fast start behind the intro" (REMINDERS 144/145): the
/// position read starts with the intro, once, and Home reuses it.
class _Loc extends LocationRepository {
  _Loc({this.permission = LocationPermission.whileInUse})
    : super(isWeb: false);

  LocationPermission permission;
  final List<String> calls = [];

  @override
  Future<bool> isLocationServiceEnabled() async {
    calls.add('service');
    return true;
  }

  @override
  Future<LocationPermission> checkPermission() async {
    calls.add('check');
    return permission;
  }

  @override
  Future<LocationPermission> requestPermission() async {
    calls.add('request');
    return permission;
  }

  @override
  Future<bool> isApproximateOnly() async => false;

  @override
  Future<GeoPoint?> lastKnownFix() async => null;

  @override
  Future<GeoPoint?> readLastGoodFix() async => null;

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    calls.add('position');
    return Position(
      latitude: 59.33,
      longitude: 18.07,
      timestamp: DateTime.now(),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
  }

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) =>
      StreamController<Position>().stream;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    StartWarmup.debugReset();
    LocationRepository.debugForgetSessionFix();
  });

  test('1. bootstrap starts the warmup before the boot steps and runApp', () {
    final src = File('lib/app/bootstrap.dart').readAsStringSync();
    final warm = src.indexOf('StartWarmup.start(');
    expect(warm, greaterThan(0), reason: 'bootstrap must start the warmup');
    expect(warm, lessThan(src.indexOf('await NativeMapsConfig.load()')));
    expect(warm, lessThan(src.indexOf('runApp(')));
  });

  test('1b. signed in + granted: one position read starts at once', () async {
    final loc = _Loc();
    await StartWarmup.start(location: loc, signedIn: () async => true);
    expect(loc.calls.where((c) => c == 'position'), hasLength(1));
    expect(StartWarmup.granted, isTrue);
  });

  test('2. not signed in: no location call at all', () async {
    final loc = _Loc();
    await StartWarmup.start(location: loc, signedIn: () async => false);
    expect(loc.calls, isEmpty);
    expect(StartWarmup.granted, isFalse);
  });

  test('3. permission not asked yet: never requested by the warmup', () async {
    final loc = _Loc(permission: LocationPermission.denied);
    await StartWarmup.start(location: loc, signedIn: () async => true);
    expect(loc.calls, isNot(contains('request')));
    expect(loc.calls, isNot(contains('position')));
    expect(StartWarmup.granted, isFalse);
  });

  test('4. Home reuses the warm fix: one position request in total', () async {
    final loc = _Loc();
    await StartWarmup.start(location: loc, signedIn: () async => true);
    final ctl = HomeLocationController(
      location: loc,
      geocoding: AppGeocoding(),
      motion: MotionEngine(),
      startCompass: () async => false,
      readCompass: () => null,
      stopCompass: () {},
    );
    final found = await ctl.detectCurrent(onQuickFix: (_) {});
    expect(found.target, isNotNull);
    expect(found.target!.latitude, closeTo(59.33, 1e-9));
    expect(loc.calls.where((c) => c == 'position'), hasLength(1));
    expect(loc.calls, isNot(contains('request')));
    ctl.dispose();
  });

  test('4b. the warm fix is the map start point when it landed', () async {
    final loc = _Loc();
    await StartWarmup.start(location: loc, signedIn: () async => true);
    await pumpEventQueue();
    final at = StartWarmup.startPoint();
    expect(at, isNotNull);
    expect(at!.latitude, closeTo(59.33, 1e-9));
  });

  test('6. an active trip wins over the warm fix', () async {
    final loc = _Loc();
    await StartWarmup.start(location: loc, signedIn: () async => true);
    await pumpEventQueue();
    const trip = GeoPoint(48.85, 2.35);
    expect(StartWarmup.startPoint(trip: trip), trip);
  });
}
