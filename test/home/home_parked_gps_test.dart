import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/core/location/app_geocoding.dart';
import 'package:movera_rider/core/location/location_repository.dart';
import 'package:movera_rider/core/motion/motion_engine.dart';
import 'package:movera_rider/features/home/application/home_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

Position _at(double lat, double lng, DateTime time) => Position(
  latitude: lat,
  longitude: lng,
  timestamp: time,
  accuracy: 4,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

/// Location allowed; each stream subscription is a fresh controller the
/// test drives by hand.
class _Location extends LocationRepository {
  _Location();

  StreamController<Position>? live;
  int streams = 0;
  Position current = _at(59.3293, 18.0686, DateTime(2026, 10, 1, 12));

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.whileInUse;

  @override
  Future<LocationPermission> requestPermission() async =>
      LocationPermission.whileInUse;

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async => current;

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    streams += 1;
    live = StreamController<Position>();
    return live!.stream;
  }
}

HomeLocationController _controller(LocationRepository location) =>
    HomeLocationController(
      location: location,
      geocoding: AppGeocoding(),
      motion: MotionEngine(),
      startCompass: () async {
        compassStarts++;
        return true;
      },
      readCompass: () => null,
      stopCompass: () {
        compassStops++;
      },
    );

int compassStarts = 0;
int compassStops = 0;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  // Finder C5: Home parks its map for the whole trip (_parkHomeMap ->
  // pauseLiveUpdates). The rider's GPS watch must stop while parked, so the
  // phone's GPS (high accuracy) is not on for the whole trip under the
  // trip screens.
  test('C5: a paused (parked) Home does not keep the GPS watch open', () async {
    final location = _Location();
    final ctl = _controller(location);
    ctl.startTracking(isMounted: () => true, onFix: (_, __) {});
    expect(location.live!.hasListener, isTrue);
    ctl.pauseLiveUpdates();
    await Future<void>.delayed(Duration.zero);
    expect(
      location.live!.hasListener,
      isFalse,
      reason: 'GPS watch still subscribed while Home is parked',
    );
  });

  test('C2: unparked Home follows the rider again (a new GPS watch)', () async {
    final location = _Location();
    final ctl = _controller(location);
    final fixes = <LatLng>[];
    ctl.startTracking(isMounted: () => true, onFix: (at, _) => fixes.add(at));
    ctl.pauseLiveUpdates();
    await Future<void>.delayed(Duration.zero);
    ctl.resumeLiveUpdates();
    expect(location.streams, 2);
    expect(location.live!.hasListener, isTrue);
    location.live!.add(_at(59.33, 18.07, DateTime(2026, 10, 1, 12, 1)));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(fixes, isNotEmpty);
  });

  test('C2: an unparked Home starts its pulse again', () {
    final location = _Location();
    final ctl = _controller(location);
    var ticks = 0;
    ctl.startPulse(isMounted: () => true, onTick: () => ticks++);
    ctl.pauseLiveUpdates();
    final before = ticks;
    ctl.resumeLiveUpdates();
    expect(ticks, greaterThan(before), reason: 'pulse started again');
  });
}
