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
      startCompass: () async => false,
      readCompass: () => null,
      stopCompass: () {},
    );

Future<void> _settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('rider-u115: allowing location again after a revoke restarts the '
      'live stream on resume', () async {
    final location = _Location();
    final ctl = _controller(location);
    final fixes = <LatLng>[];
    ctl.startTracking(isMounted: () => true, onFix: (at, _) => fixes.add(at));
    expect(location.streams, 1);
    location.live!.add(_at(59.3293, 18.0686, DateTime(2026, 10, 1, 12)));
    await _settle();
    expect(fixes, hasLength(1));

    // Revoked in Settings: the stream reports it and tracking stops.
    location.live!.addError(const PermissionDeniedException('revoked'));
    await _settle();
    expect(ctl.state, HomeLocationState.permissionRequired);

    // Allowed again; the rider comes back to the app.
    ctl.pauseLiveUpdates();
    ctl.resumeLiveUpdates();
    await _settle();
    expect(ctl.state, HomeLocationState.live);
    expect(location.streams, 2, reason: 'the live stream must be resubscribed');

    // The rider walks on: the puck follows.
    final before = fixes.length;
    location.live!.add(_at(59.3310, 18.0686, DateTime(2026, 10, 1, 12, 1)));
    await _settle();
    expect(fixes.length, before + 1);
    ctl.dispose();
  });

  group('rider-u116: the web puck does not swap bitmaps on a timer', () {
    HomeLocationController pulsing({required bool web}) =>
        HomeLocationController(
          location: _Location(),
          geocoding: AppGeocoding(),
          motion: MotionEngine(),
          startCompass: () async => false,
          readCompass: () => null,
          stopCompass: () {},
          pulseAnimates: !web,
        );

    testWidgets('web: one paint, no pulse ticks', (tester) async {
      final ctl = pulsing(web: true);
      var ticks = 0;
      ctl.startPulse(isMounted: () => true, onTick: () => ticks += 1);
      await tester.pump(const Duration(seconds: 10));
      expect(ticks, 1);
      expect(ctl.pulseExpanded, isFalse);
      ctl.dispose();
    });

    testWidgets('Android/iOS keep the pulse', (tester) async {
      final ctl = pulsing(web: false);
      var ticks = 0;
      ctl.startPulse(isMounted: () => true, onTick: () => ticks += 1);
      await tester.pump(const Duration(milliseconds: 1800));
      expect(ticks, 3);
      ctl.dispose();
    });
  });
}
