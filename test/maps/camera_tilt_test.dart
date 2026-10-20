// Rider camera = driver camera (driver PRs #309/#311): tilt proportional to
// zoom (0° at zoom 12, linear to 67.5° at 15.5), tilt never blocks zoom,
// nothing moves under a finger, no stale pose restored on idle, one
// continuous glide that a newer goal retargets instead of restarting.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/core/maps/camera_tilt.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/maps/google_map_provider.dart';
import 'package:movera_rider/core/maps/map_camera_controller.dart';
import 'package:movera_rider/core/maps/map_camera_motion.dart';
import 'package:movera_rider/features/home/presentation/home.dart'
    show homeOpeningZoom;
import 'package:movera_rider/shared/widgets/custom_google_map.dart';

/// Records camera commands instead of driving a platform map.
class _FakeMap extends Fake implements GoogleMapController {
  final List<(String, List<dynamic>)> calls = [];

  @override
  Future<void> animateCamera(CameraUpdate cameraUpdate, {Duration? duration}) {
    calls.add(('animate', cameraUpdate.toJson() as List<dynamic>));
    return Future<void>.value();
  }

  @override
  Future<void> moveCamera(CameraUpdate cameraUpdate) {
    calls.add(('move', cameraUpdate.toJson() as List<dynamic>));
    return Future<void>.value();
  }

  @override
  Future<String?> getStyleError() async => null;

  List<Map<String, Object?>> get poses => [
    for (final call in calls)
      if (call.$2.first == 'newCameraPosition')
        (call.$2[1] as Map<Object?, Object?>).cast<String, Object?>(),
  ];
}

double _tilt(Map<String, Object?> pose) => (pose['tilt']! as num).toDouble();
double _zoom(Map<String, Object?> pose) => (pose['zoom']! as num).toDouble();
List<double> _target(Map<String, Object?> pose) => [
  for (final v in pose['target']! as List<Object?>) (v! as num).toDouble(),
];

const _stockholm = LatLng(59.33, 18.06);

/// Pumps 16 ms frames until [done] or [limit] frames.
Future<void> _frames(
  WidgetTester tester, {
  int limit = 400,
  bool Function()? done,
}) async {
  for (var i = 0; i < limit && !(done?.call() ?? false); i++) {
    await tester.pump(cameraEaseFrame);
  }
}

void main() {
  tearDown(() => MapView.now = DateTime.now);

  group('tilt is proportional to zoom (driver curve)', () {
    test('0° at zoom 12, linear to 67.5° at zoom 15.5', () {
      expect(tiltForZoom(8), 0);
      expect(tiltForZoom(11), 0);
      // Home opens flat.
      expect(tiltForZoom(homeOpeningZoom), 0);
      expect(tiltForZoom(12), 0);
      expect(tiltForZoom(13), closeTo(67.5 / 3.5, 1e-9));
      expect(tiltForZoom(13.75), closeTo(33.75, 1e-9));
      expect(tiltForZoom(14), closeTo(67.5 * 2 / 3.5, 1e-9));
      expect(tiltForZoom(15), closeTo(67.5 * 3 / 3.5, 1e-9));
      expect(tiltForZoom(15.5), maxMapTilt);
      expect(tiltForZoom(17), maxMapTilt);
      expect(tiltForZoom(21), maxMapTilt);
      expect(tiltForZoom(double.nan), 0);
    });

    test('every small zoom step changes the tilt by the same amount', () {
      for (var z = 12.0; z < 15.49; z += .05) {
        final step = tiltForZoom(z + .05) - tiltForZoom(z);
        expect(step, closeTo(67.5 / 3.5 * .05, 1e-6), reason: 'at $z');
        expect(
          tiltForZoom(z),
          lessThanOrEqualTo(maxTiltForZoom(z)),
          reason: 'never clamped by the engine at $z',
        );
      }
    });

    test('the engine envelope: 30° to zoom 10, 45° at 14, 67.5° at 15.5', () {
      expect(maxTiltForZoom(8), 30);
      expect(maxTiltForZoom(10), 30);
      expect(maxTiltForZoom(14), 45);
      expect(maxTiltForZoom(15.5), maxMapTilt);
      expect(maxTiltForZoom(19), maxMapTilt);
    });
  });

  group('programmatic camera moves', () {
    late GoogleMapProvider maps;
    late _FakeMap fake;

    setUp(() {
      maps = GoogleMapProvider();
      fake = _FakeMap();
      maps.attach(fake, owner: 'home');
    });

    test('a first move lands at once with the tilt of its zoom', () async {
      await maps.animateCamera(const GeoPoint(59.33, 18.06), zoom: 17);
      expect(fake.calls.single.$1, 'move');
      expect(_tilt(fake.poses.single), maxMapTilt);
    });

    test('Home at zoom 11.7 is flat', () async {
      await maps.animateCamera(
        const GeoPoint(59.33, 18.06),
        zoom: homeOpeningZoom,
      );
      expect(_tilt(fake.poses.single), 0);
      expect(_zoom(fake.poses.single), 11.7);
    });

    test('recenter is street zoom 15 with that zoom\'s tilt', () async {
      final camera = MapCameraController(maps);
      await camera.followUser(const GeoPoint(59.33, 18.06));
      expect(recenterZoom, 15);
      expect(_zoom(fake.poses.single), 15);
      expect(_tilt(fake.poses.single), closeTo(tiltForZoom(15), 1e-9));
      expect(_tilt(fake.poses.single), greaterThan(57));
      // A recentred map hides the recenter button.
      expect(camera.showRecenter(zoom: 15, metersFromUser: 0), isFalse);
      expect(camera.showRecenter(zoom: 13, metersFromUser: 0), isTrue);
    });

    test('a whole-route fit is flat, a close fit leans', () async {
      mapViewOf(fake).size = const Size(390, 700);
      // Stockholm → Arlanda: an overview, zoom ~10.
      await maps.fitBounds(
        const GeoPoint(59.3293, 18.0686),
        const GeoPoint(59.6519, 17.9186),
      );
      expect(_zoom(fake.poses.single), lessThan(11));
      expect(_tilt(fake.poses.single), 0);

      fake.calls.clear();
      mapViewOf(fake).pose = null; // Land at once instead of gliding.
      // Driver ~300 m from the pickup: a close fit.
      await maps.fitBounds(
        const GeoPoint(59.3293, 18.0686),
        const GeoPoint(59.3313, 18.0716),
      );
      final pose = fake.poses.single;
      expect(_zoom(pose), greaterThan(14));
      expect(_tilt(pose), closeTo(tiltForZoom(_zoom(pose)), 1e-9));
      expect(_tilt(pose), greaterThan(40));
      expect(_target(pose)[0], closeTo(59.3303, 0.0002));
      expect(_target(pose)[1], closeTo(18.0701, 0.0002));
    });

    test('without a known viewport the plain bounds fit is kept', () async {
      await maps.fitBounds(
        const GeoPoint(59.3293, 18.0686),
        const GeoPoint(59.6519, 17.9186),
      );
      expect(fake.calls.single.$2.first, 'newLatLngBounds');
    });

    test('a map that stays flat never tilts', () async {
      mapViewOf(fake).tiltWithZoom = false;
      await maps.animateCamera(const GeoPoint(59.33, 18.06), zoom: 17);
      expect(_tilt(fake.poses.single), 0);
    });

    test('a raster web map keeps the plain bounds fit', () async {
      mapViewOf(fake)
        ..size = const Size(390, 700)
        ..supportsTilt = false;
      await maps.fitBounds(
        const GeoPoint(59.3293, 18.0686),
        const GeoPoint(59.3313, 18.0716),
      );
      expect(fake.calls.single.$2.first, 'newLatLngBounds');
    });
  });

  group('the camera never moves under a finger', () {
    late GoogleMapProvider maps;
    late _FakeMap fake;

    setUp(() {
      maps = GoogleMapProvider();
      fake = _FakeMap();
      maps.attach(fake, owner: 'waiting');
    });

    test('no command moves a held map, not even a recenter', () async {
      mapViewOf(fake)
        ..size = const Size(390, 700)
        ..touching = true;
      await maps.animateCamera(const GeoPoint(59.33, 18.06), zoom: 15);
      await maps.fitBounds(
        const GeoPoint(59.3293, 18.0686),
        const GeoPoint(59.3313, 18.0716),
        follow: true,
      );
      await maps.moveCamera(const GeoPoint(59.33, 18.06));
      expect(fake.calls, isEmpty);
    });

    test('follow updates wait 12 s after a hand move; recenter takes the map '
        'back at once', () async {
      var clock = DateTime(2026, 10, 19, 12);
      MapView.now = () => clock;
      final view = mapViewOf(fake)..movedByHandAt = clock;
      await maps.fitBounds(
        const GeoPoint(59.3293, 18.0686),
        const GeoPoint(59.3313, 18.0716),
        follow: true,
      );
      await maps.animateCamera(
        const GeoPoint(59.33, 18.06),
        zoom: 11.7,
        follow: true,
      );
      expect(fake.calls, isEmpty, reason: 'the rider just moved the map');
      clock = clock.add(const Duration(seconds: 13));
      await maps.animateCamera(
        const GeoPoint(59.33, 18.06),
        zoom: 11.7,
        follow: true,
      );
      expect(fake.calls, hasLength(1), reason: 'the hold has run out');

      fake.calls.clear();
      view
        ..movedByHandAt = clock
        ..pose = null;
      await maps.animateCamera(const GeoPoint(59.33, 18.06), zoom: 15);
      expect(fake.calls, hasLength(1), reason: 'recenter is the rider\'s ask');
      expect(view.movedByHandAt, isNull);
    });
  });

  group('one continuous glide', () {
    testWidgets('every frame carries the tilt of its own zoom (live tilt)', (
      tester,
    ) async {
      final fake = _FakeMap();
      final view = mapViewOf(fake)
        ..pose = const CameraPosition(target: _stockholm, zoom: 11.7);
      var done = false;
      unawaited(
        easeCameraTo(
          fake,
          CameraPosition(
            target: const LatLng(59.331, 18.061),
            zoom: 15,
            tilt: tiltForZoom(15),
          ),
        ).then((_) => done = true),
      );
      await _frames(tester, done: () => done);
      expect(done, isTrue);
      final poses = fake.poses;
      expect(poses.length, greaterThan(20), reason: 'small steps, no cut');
      var lastZoom = 11.7;
      for (final pose in poses) {
        expect(
          _tilt(pose),
          closeTo(tiltForZoom(_zoom(pose)), 1e-6),
          reason: 'tilt rides with the zoom at ${_zoom(pose)}',
        );
        expect(_zoom(pose), greaterThanOrEqualTo(lastZoom));
        expect(_zoom(pose) - lastZoom, lessThan(0.15), reason: 'no jump');
        lastZoom = _zoom(pose);
      }
      expect(_zoom(poses.last), 15);
      expect(view.easing, isFalse);
    });

    testWidgets('a newer goal retargets the glide: no restart stutter', (
      tester,
    ) async {
      final fake = _FakeMap();
      mapViewOf(fake).pose = const CameraPosition(target: _stockholm, zoom: 13);
      // The trip map refits on every driver position, ~every 400 ms.
      var target = 59.33;
      Future<void> fit() => easeCameraTo(
        fake,
        CameraPosition(target: LatLng(target, 18.06), zoom: 13),
      );
      unawaited(fit());
      for (var fix = 0; fix < 6; fix++) {
        await _frames(tester, limit: 25);
        target += 0.0004;
        unawaited(fit());
      }
      await _frames(tester, limit: 30);
      final lats = [for (final p in fake.poses) _target(p)[0]];
      final steps = [
        for (var i = 1; i < lats.length; i++) lats[i] - lats[i - 1],
      ];
      // Moving towards the newest goal the whole time: the camera never
      // stops and re-accelerates from rest at a new command.
      for (var i = 0; i < 25 * 6; i++) {
        expect(steps[i], greaterThan(0), reason: 'frame $i stalled');
      }
      // One glide, retargeted: a restart would show a step falling back to
      // a near-zero start after every fix.
      for (var fix = 1; fix < 6; fix++) {
        final at = fix * 25;
        expect(
          steps[at],
          greaterThan(steps[at - 1] * 0.5),
          reason: 'fix $fix restarted from rest',
        );
      }
      mapViewOf(fake).interrupt();
      await tester.pump(cameraEaseFrame);
    });

    testWidgets('a finger stops a running glide at once', (tester) async {
      final fake = _FakeMap();
      final view = mapViewOf(fake)
        ..pose = const CameraPosition(target: _stockholm, zoom: 12);
      unawaited(
        easeCameraTo(fake, const CameraPosition(target: _stockholm, zoom: 16)),
      );
      await _frames(tester, limit: 5);
      view.touching = true;
      final count = fake.calls.length;
      await _frames(tester, limit: 60);
      expect(fake.calls.length, count);
      expect(view.easing, isFalse);
    });
  });

  group('tilt ease after the rider zooms', () {
    testWidgets('a repeated idle keeps the ease going (no restart stutter)', (
      tester,
    ) async {
      final fake = _FakeMap();
      mapViewOf(fake).pose = const CameraPosition(
        target: _stockholm,
        zoom: 14.2,
      );
      var done = false;
      unawaited(easeTiltTo(fake, 40).then((_) => done = true));
      for (var i = 0; i < 400 && !done; i++) {
        // Maps reports idle between the ease's own frames.
        if (i % 3 == 1) unawaited(easeTiltTo(fake, 40));
        await tester.pump(cameraEaseFrame);
      }
      expect(done, isTrue);
      final tilts = [for (final p in fake.poses) _tilt(p)];
      expect(tilts.last, 40);
      for (var i = 1; i < tilts.length; i++) {
        expect(
          tilts[i],
          greaterThan(tilts[i - 1]),
          reason: 'frame $i restarted the ease',
        );
      }
      for (final p in fake.poses) {
        expect(_zoom(p), 14.2, reason: 'the ease never changes the zoom');
      }
    });

    testWidgets('each frame keeps the latest zoom: tilt never blocks zoom', (
      tester,
    ) async {
      final fake = _FakeMap();
      final view = mapViewOf(fake)
        ..pose = const CameraPosition(target: _stockholm, zoom: 13);
      unawaited(easeTiltTo(fake, 30));
      await _frames(tester, limit: 3);
      final count = fake.calls.length;
      // The camera's zoom changes mid-ease (an app frame elsewhere).
      view.pose = CameraPosition(
        target: const LatLng(59.331, 18.061),
        zoom: 14.5,
        tilt: view.pose!.tilt,
      );
      await _frames(tester, limit: 40);
      expect(fake.calls.length, greaterThan(count + 5));
      for (final p in fake.poses.skip(count)) {
        expect(_zoom(p), 14.5, reason: 'the zoom is never pulled back');
        expect(_target(p), [59.331, 18.061]);
      }
    });
  });

  group('pinch on CustomGoogleMap', () {
    Future<(_FakeMap, GoogleMap)> pumpMap(
      WidgetTester tester, {
      bool tiltWithZoom = true,
      CameraPosition? initial,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 390,
              height: 500,
              child: CustomGoogleMap(
                cloudMapId: '',
                tiltWithZoom: tiltWithZoom,
                initialPosition: initial,
              ),
            ),
          ),
        ),
      );
      final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
      final fake = _FakeMap();
      map.onMapCreated!(fake);
      return (fake, map);
    }

    Offset centre(WidgetTester tester) =>
        tester.getCenter(find.byType(GoogleMap));

    /// Two fingers pinch; the map reports [toZoom] meanwhile.
    Future<(TestGesture, TestGesture)> pinch(
      WidgetTester tester,
      GoogleMap map,
      double toZoom, {
      double tilt = 0,
    }) async {
      final a = await tester.startGesture(centre(tester), pointer: 1);
      final b = await tester.startGesture(
        centre(tester) + const Offset(40, 0),
        pointer: 2,
      );
      await b.moveBy(const Offset(60, 0));
      map.onCameraMoveStarted!();
      map.onCameraMove!(
        CameraPosition(target: _stockholm, zoom: toZoom, bearing: 20, tilt: tilt),
      );
      return (a, b);
    }

    testWidgets('the map opens with the tilt of its zoom', (tester) async {
      final (_, map) = await pumpMap(
        tester,
        initial: const CameraPosition(target: _stockholm, zoom: 14),
      );
      expect(map.initialCameraPosition.tilt, closeTo(tiltForZoom(14), 1e-9));
      final (_, flat) = await pumpMap(
        tester,
        tiltWithZoom: false,
        initial: const CameraPosition(target: _stockholm, zoom: 14),
      );
      expect(flat.initialCameraPosition.tilt, 0);
    });

    testWidgets('idle under a held pinch waits; letting go eases only the '
        'tilt, at the zoom the rider left', (tester) async {
      final (fake, map) = await pumpMap(tester);
      final (a, b) = await pinch(tester, map, 15);
      map.onCameraIdle!(); // Maps idles while the fingers rest.
      await _frames(tester, limit: 30);
      expect(fake.calls, isEmpty, reason: 'nothing moves under the finger');
      await b.up();
      expect(fake.calls, isEmpty, reason: 'one finger is still down');
      await a.up();
      await _frames(tester, limit: 40);
      final poses = fake.poses;
      expect(_tilt(poses.last), closeTo(tiltForZoom(15), 1e-9));
      for (final pose in poses) {
        expect(_zoom(pose), 15, reason: 'no stale zoom restored');
        expect(pose['bearing'], 20);
        expect(_target(pose), [_stockholm.latitude, _stockholm.longitude]);
      }
    });

    testWidgets('zooming out flattens', (tester) async {
      final (fake, map) = await pumpMap(tester);
      mapViewOf(fake).pose = const CameraPosition(
        target: _stockholm,
        zoom: 16,
        tilt: maxMapTilt,
      );
      final (a, b) = await pinch(tester, map, 11.5, tilt: maxMapTilt);
      await b.up();
      await a.up();
      map.onCameraIdle!();
      await _frames(tester, limit: 40);
      expect(_tilt(fake.poses.last), 0);
      expect(_zoom(fake.poses.last), 11.5);
    });

    testWidgets('a pinch during a running tilt ease is never undone', (
      tester,
    ) async {
      final (fake, map) = await pumpMap(tester);
      // The rider zoomed to 14 and let go: the tilt eases towards 38.6°.
      var (a, b) = await pinch(tester, map, 14);
      await b.up();
      await a.up();
      map.onCameraIdle!();
      await _frames(tester, limit: 6);
      expect(_tilt(fake.poses.last), inExclusiveRange(0, tiltForZoom(14)));
      // A finger lands mid-ease and pinches the map to zoom 15.6, where the
      // web layer has already tilted it with the zoom.
      final count = fake.calls.length;
      (a, b) = await pinch(tester, map, 15.6, tilt: maxMapTilt);
      map.onCameraIdle!();
      await _frames(tester, limit: 60);
      expect(fake.calls.length, count, reason: 'the ease stopped under it');
      await b.up();
      await a.up();
      await _frames(tester, limit: 60);
      for (final pose in fake.poses.skip(count)) {
        expect(_zoom(pose), 15.6, reason: 'the zoom is never reset');
      }
      expect(mapViewOf(fake).pose!.zoom, 15.6);
    });

    testWidgets('a programmatic move alone never triggers a tilt ease', (
      tester,
    ) async {
      final (fake, map) = await pumpMap(tester);
      map.onCameraMove!(const CameraPosition(target: _stockholm, zoom: 15));
      map.onCameraIdle!();
      await _frames(tester, limit: 30);
      expect(fake.calls, isEmpty);
    });

    testWidgets('a flat map (pickup pin screens) is never tilted', (
      tester,
    ) async {
      final (fake, map) = await pumpMap(tester, tiltWithZoom: false);
      final (a, b) = await pinch(tester, map, 17);
      await b.up();
      await a.up();
      map.onCameraIdle!();
      await _frames(tester, limit: 30);
      expect(fake.calls, isEmpty);
      expect(mapViewOf(fake).tiltWithZoom, isFalse);
    });

    testWidgets('a pinch makes the map the rider\'s: follow updates wait', (
      tester,
    ) async {
      final (fake, map) = await pumpMap(tester);
      final maps = GoogleMapProvider()..attach(fake, owner: 'waiting');
      final (a, b) = await pinch(tester, map, 15);
      await b.up();
      await a.up();
      await _frames(tester, limit: 40);
      fake.calls.clear();
      await maps.animateCamera(
        const GeoPoint(59.4, 18.1),
        zoom: 13,
        follow: true,
      );
      expect(fake.calls, isEmpty);
      expect(mapViewOf(fake).movedByHandAt, isNotNull);
    });
  });
}
