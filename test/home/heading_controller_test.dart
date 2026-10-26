import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/core/location/app_geocoding.dart';
import 'package:movera_rider/core/location/location_repository.dart';
import 'package:movera_rider/core/motion/bearing.dart';
import 'package:movera_rider/core/motion/motion_engine.dart';
import 'package:movera_rider/features/home/application/home_controller.dart';

class _FakeCompass {
  bool granted = true;
  int starts = 0;
  int stops = 0;
  double? value;

  Future<bool> start() async {
    starts += 1;
    return granted;
  }

  double? read() => granted ? value : null;

  void stop() {
    stops += 1;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  HomeLocationController controllerOf(_FakeCompass compass) {
    return HomeLocationController(
      location: LocationRepository(),
      geocoding: AppGeocoding(),
      motion: MotionEngine(),
      startCompass: compass.start,
      readCompass: compass.read,
      stopCompass: compass.stop,
    );
  }

  test('heading permission granted starts compass polling', () async {
    final compass = _FakeCompass()..value = 40;
    final ctl = controllerOf(compass);
    final granted = await ctl.startHeading(
      isMounted: () => true,
      onHeading: (_) {},
    );
    expect(granted, isTrue);
    expect(compass.starts, 1);
    ctl.pollHeading();
    expect(ctl.hasCompassHeading, isTrue);
    expect(ctl.heading, closeTo(blendHeading(0, 40), 0.001));
    ctl.dispose();
  });

  test('heading permission denied falls back to GPS course', () async {
    final compass = _FakeCompass()
      ..granted = false
      ..value = 90;
    final ctl = controllerOf(compass)..heading = 45;
    final granted = await ctl.startHeading(
      isMounted: () => true,
      onHeading: (_) {},
    );
    expect(granted, isFalse);
    ctl.pollHeading();
    expect(ctl.hasCompassHeading, isFalse);
    expect(ctl.heading, 45);
    ctl.dispose();
  });

  test('compass heading changes while GPS position stays fixed', () async {
    final compass = _FakeCompass()..value = 0;
    final ctl = controllerOf(compass);
    const parked = LatLng(59.3293, 18.0686);
    await ctl.startHeading(isMounted: () => true, onHeading: (_) {});
    ctl.paintUserPuck(
      target: parked,
      icon: BitmapDescriptor.defaultMarker,
      heading: 0,
    );
    compass.value = 90;
    for (var i = 0; i < 12; i++) {
      ctl.pollHeading();
    }
    expect(ctl.hasCompassHeading, isTrue);
    expect(ctl.heading, closeTo(90, 8));
    expect(ctl.markers.single.position, parked);
    ctl.paintUserPuck(
      target: parked,
      icon: BitmapDescriptor.defaultMarker,
      heading: ctl.heading,
    );
    expect(ctl.markers.single.position, parked);
    expect(ctl.markers.single.rotation, closeTo(ctl.heading, 0.001));
    ctl.dispose();
  });

  test('350 to 10 uses shortest-angle rotation', () async {
    final compass = _FakeCompass()..value = 10;
    final ctl = controllerOf(compass)..heading = 350;
    await ctl.startHeading(isMounted: () => true, onHeading: (_) {});
    final before = ctl.heading;
    ctl.pollHeading();
    final step = shortestTurn(before, ctl.heading);
    expect(step, greaterThan(0));
    expect(step, lessThan(20));
    expect(ctl.heading, isNot(inInclusiveRange(20, 340)));
    for (var i = 0; i < 24; i++) {
      ctl.pollHeading();
    }
    expect(ctl.heading, closeTo(10, 1.5));
    ctl.dispose();
  });

  test('repeated startHeading does not open compass twice', () async {
    final compass = _FakeCompass()..value = 12;
    final ctl = controllerOf(compass);
    final first = await ctl.startHeading(
      isMounted: () => true,
      onHeading: (_) {},
    );
    final second = await ctl.startHeading(
      isMounted: () => true,
      onHeading: (_) {},
    );
    expect(first, isTrue);
    expect(second, isTrue);
    expect(compass.starts, 1);
    ctl.dispose();
    expect(compass.stops, 1);
  });

  test('denied start can retry after a later grant', () async {
    final compass = _FakeCompass()..granted = false;
    final ctl = controllerOf(compass);
    expect(
      await ctl.startHeading(isMounted: () => true, onHeading: (_) {}),
      isFalse,
    );
    compass.granted = true;
    compass.value = 15;
    expect(
      await ctl.startHeading(isMounted: () => true, onHeading: (_) {}),
      isTrue,
    );
    expect(compass.starts, 2);
    ctl.pollHeading();
    expect(ctl.hasCompassHeading, isTrue);
    ctl.dispose();
  });

  test('GPS heading is left alone when compass samples are missing', () async {
    final compass = _FakeCompass()
      ..granted = true
      ..value = null;
    final ctl = controllerOf(compass)..heading = 200;
    await ctl.startHeading(isMounted: () => true, onHeading: (_) {});
    ctl.pollHeading();
    expect(ctl.hasCompassHeading, isFalse);
    expect(ctl.heading, 200);
    ctl.dispose();
  });

  group('the puck holds still while the map camera moves', () {
    test(
      'a compass turn under a moving camera repaints once it rests',
      () async {
        var now = DateTime(2026, 10, 20, 12);
        final compass = _FakeCompass()..value = 90;
        final ctl = HomeLocationController(
          location: LocationRepository(),
          geocoding: AppGeocoding(),
          motion: MotionEngine(),
          startCompass: compass.start,
          readCompass: compass.read,
          stopCompass: compass.stop,
          clock: () => now,
        );
        final delivered = <double>[];
        await ctl.startHeading(isMounted: () => true, onHeading: delivered.add);
        ctl.noteCameraMove(bearing: 30);
        expect(ctl.cameraMoving, isTrue);
        expect(ctl.lastMapBearing, 30);
        ctl.pollHeading();
        expect(delivered, isEmpty, reason: 'no repaint under a moving camera');
        expect(
          ctl.heading,
          isNot(0),
          reason: 'the heading itself still tracks',
        );
        now = now.add(HomeLocationController.cameraQuietPeriod);
        expect(ctl.cameraMoving, isFalse);
        ctl.pollHeading();
        expect(delivered, hasLength(1));
        expect(delivered.single, closeTo(ctl.heading, 1e-9));
        ctl.dispose();
      },
    );

    testWidgets('the pulse pauses while the camera moves', (tester) async {
      var now = DateTime(2026, 10, 20, 12);
      final ctl = HomeLocationController(
        location: LocationRepository(),
        geocoding: AppGeocoding(),
        motion: MotionEngine(),
        startCompass: () async => false,
        readCompass: () => null,
        stopCompass: () {},
        clock: () => now,
      );
      var ticks = 0;
      ctl.startPulse(isMounted: () => true, onTick: () => ticks += 1);
      expect(ticks, 1);
      await tester.pump(const Duration(milliseconds: 850));
      expect(ticks, 2);
      expect(ctl.pulseExpanded, isTrue);
      // A pinch: the camera reports moves all through the next tick.
      ctl.noteCameraMove();
      await tester.pump(const Duration(milliseconds: 850));
      expect(ticks, 2);
      expect(ctl.pulseExpanded, isTrue);
      // A finger holds the map still: no camera reports, still no pulse.
      now = now.add(const Duration(seconds: 1));
      var held = true;
      ctl.mapBusy = () => held;
      await tester.pump(const Duration(milliseconds: 850));
      expect(ticks, 2);
      held = false;
      await tester.pump(const Duration(milliseconds: 850));
      expect(ticks, 3);
      expect(ctl.pulseExpanded, isFalse);
      ctl.dispose();
    });
  });
}
