import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:movera_rider/core/location/geocoding_repository.dart';
import 'package:movera_rider/core/location/location_repository.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/motion/motion_engine.dart';
import 'package:movera_rider/features/home/application/home_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Audit phase 6: what one minute of live GPS costs on Home. A phone in a
/// moving car delivers about one fix a second past the distance filter,
/// the compass turns all the time, and the puck pulses. Every callback here
/// repaints the puck (a new marker set, a map widget rebuild and a marker
/// update over the platform channel), so each is counted and bounded.
///
/// Measured on this branch (60 fixes in 60 s, a compass that jitters
/// ±0.8° every sample): 1653 puck repaints (~27.5 a fix: the 420 ms glide
/// on painted frames), 3 heading repaints, 71 pulse ticks, 0 network
/// requests (the controller's only geocode is the first fix's address;
/// Home's own relabel asks again only after a 75 m move).
class _Location extends LocationRepository {
  final StreamController<Position> fixes = StreamController<Position>();

  @override
  Future<bool> isLocationServiceEnabled() async => true;
  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.whileInUse;
  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) =>
      Completer<Position>().future;
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
      fixes.stream;
}

class _Geocoding extends GeocodingRepository {
  int calls = 0;
  @override
  Future<PlaceResult?> forward(String query) async {
    calls += 1;
    return null;
  }

  @override
  Future<String?> reverse(GeoPoint point) async {
    calls += 1;
    return 'Street';
  }
}

Position _at(int second) => Position(
  // About 14 m/s north: past the 8 m (phone) / 20 m (web) filter each second.
  latitude: 59.19 + second * 0.000126,
  longitude: 17.62,
  timestamp: DateTime.utc(2026, 10, 27, 12, 0, second),
  accuracy: 8,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 14,
  speedAccuracy: 1,
);

/// Budgets for one minute (fixes once a second).
const int fixesPerMinute = 60;

/// Each fix glides the puck over MotionEngine.window (420 ms) on painted
/// frames: about 27 repaints at 60 fps, never a glide that keeps going.
const int puckRepaintsPerMinute = fixesPerMinute * 28;

/// UI-12: compass repaints at most every 250 ms unless it turned >= the
/// repaint step; a hand-held jitter stays under that step.
const int headingRepaintsPerMinute = 4 * 60 + 1;

/// The puck pulse: one swap every 850 ms on phones (none on the web).
const int pulseTicksPerMinute = 60000 ~/ 850 + 1;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('one minute of live GPS stays within its repaint budget', (
    tester,
  ) async {
    final location = _Location();
    final geocoding = _Geocoding();
    var compass = 0.0;
    final ctl = HomeLocationController(
      location: location,
      geocoding: geocoding,
      motion: MotionEngine(),
      startCompass: () async => true,
      readCompass: () => compass = compass > 0 ? -0.8 : 0.8,
      stopCompass: () {},
      compassSupported: true,
      pulseAnimates: true,
    );
    var puck = 0, headings = 0, pulses = 0;
    await ctl.bindLiveLocation(
      isMounted: () => true,
      onFix: (_, __) => puck += 1,
      onHeading: (_) => headings += 1,
      onPulse: () => pulses += 1,
    );
    for (var second = 0; second < fixesPerMinute; second++) {
      location.fixes.add(_at(second));
      for (var frame = 0; frame < 60; frame++) {
        await tester.pump(const Duration(microseconds: 16667));
      }
    }

    expect(puck, greaterThanOrEqualTo(fixesPerMinute), reason: 'every fix');
    expect(puck, lessThanOrEqualTo(puckRepaintsPerMinute));
    expect(headings, lessThanOrEqualTo(headingRepaintsPerMinute));
    expect(pulses, lessThanOrEqualTo(pulseTicksPerMinute));
    expect(geocoding.calls, 0, reason: 'no request per fix');

    ctl.dispose();
    unawaited(location.fixes.close());
  });
}
