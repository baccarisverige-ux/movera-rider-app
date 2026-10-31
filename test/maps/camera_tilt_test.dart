// Rider camera = driver camera (driver PRs #309/#311): tilt proportional to
// zoom (0° at zoom 12, linear to 67.5° at 15.5), tilt never blocks zoom,
// nothing moves under a finger, no stale pose restored on idle, one
// continuous glide that a newer goal retargets instead of restarting.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/core/maps/camera_tilt.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/maps/google_map_provider.dart';
import 'package:movera_rider/core/maps/map_camera_controller.dart';
import 'package:movera_rider/core/maps/map_camera_motion.dart';
import 'package:movera_rider/core/web/rider_map_bridge.dart';
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

/// The glide measures each frame with [MapView.now]; a still clock makes
/// every pumped frame exactly one frame, however loaded the machine is.
void _stillClock() => MapView.now = () => DateTime(2026);

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

    test('recenter is the owner\'s zoom 13.8 with that zoom\'s tilt', () async {
      final camera = MapCameraController(maps);
      await camera.followUser(const GeoPoint(59.33, 18.06));
      expect(recenterZoom, 13.8);
      expect(_zoom(fake.poses.single), 13.8);
      expect(_tilt(fake.poses.single), closeTo(tiltForZoom(13.8), 1e-9));
      expect(_tilt(fake.poses.single), closeTo(67.5 * 1.8 / 3.5, 1e-9));
      // A recentred map hides the recenter button; so does the rider's own
      // closer pinch on the same spot. Zoomed well out, it shows.
      expect(camera.showRecenter(zoom: 13.8, metersFromUser: 0), isFalse);
      expect(camera.showRecenter(zoom: 16, metersFromUser: 0), isFalse);
      expect(camera.showRecenter(zoom: 13, metersFromUser: 0), isTrue);
      expect(camera.showRecenter(zoom: 13.8, metersFromUser: 80), isTrue);
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

    test('N6: a route of a few metres fits at the street zoom, flat, not at '
        'building level with the full tilt', () async {
      // Owner screenshot (Select ride, Klockarvägen 37, Södertälje): pickup
      // and destination a few metres apart fitted at zoom ~21 with 67.5° of
      // tilt, a street-level view with the route drawn as a wedge.
      mapViewOf(fake)
        ..size = const Size(390, 700)
        ..tiltWithZoom = false;
      await maps.fitBounds(
        const GeoPoint(59.1962, 17.6279),
        const GeoPoint(59.19625, 17.6281),
      );
      final pose = fake.poses.single;
      expect(_zoom(pose), lessThanOrEqualTo(routeFitMaxZoom));
      expect(_zoom(pose), greaterThan(routeFitMaxZoom - 1));
      expect(_tilt(pose), 0);
    });

    test('N6: the same cap when the viewport is not known yet', () async {
      await maps.fitBounds(
        const GeoPoint(59.1962, 17.6279),
        const GeoPoint(59.19625, 17.6281),
      );
      final call = fake.calls.single.$2;
      expect(call.first, 'newLatLngZoom');
      expect((call[2] as num).toDouble(), routeFitMaxZoom);
      expect(
        GoogleMapProvider.boundsFitPastStreetZoom(
          const LatLng(59.3293, 18.0686),
          const LatLng(59.3429, 18.0496),
        ),
        isFalse,
        reason: 'a real route still gets the bounds fit',
      );
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
      _stillClock();
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
      // rider-cam-1: 3.3 zoom levels settle in about 0.65 s (they crept on
      // for 2-3 s), so the fastest frame steps ~0.27 levels (was ~0.1);
      // the glide still gains speed over several frames, never in one.
      expect(poses.length, lessThan(45), reason: 'settles well under 1 s');
      var lastZoom = 11.7;
      for (final pose in poses) {
        expect(
          _tilt(pose),
          closeTo(tiltForZoom(_zoom(pose)), 1e-6),
          reason: 'tilt rides with the zoom at ${_zoom(pose)}',
        );
        expect(_zoom(pose), greaterThanOrEqualTo(lastZoom));
        expect(_zoom(pose) - lastZoom, lessThan(0.3), reason: 'no jump');
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
      // The trip map refits on every driver position. rider-cam-1: the
      // glide now settles in well under a second, so the goals here come
      // every 100 ms (6 frames), 0.002° (~23 px) apart, to keep it moving.
      var target = 59.33;
      Future<void> fit() => easeCameraTo(
        fake,
        CameraPosition(target: LatLng(target, 18.06), zoom: 13),
      );
      unawaited(fit());
      for (var fix = 0; fix < 6; fix++) {
        await _frames(tester, limit: 6);
        target += 0.002;
        unawaited(fit());
      }
      await _frames(tester, limit: 40);
      final lats = [for (final p in fake.poses) _target(p)[0]];
      expect(lats.last, target, reason: 'it lands on the newest goal');
      final steps = [
        for (var i = 1; i < lats.length; i++) lats[i] - lats[i - 1],
      ];
      // Moving towards the newest goal the whole time: the camera never
      // stops and re-accelerates from rest at a new command.
      for (var i = 0; i < 6 * 6; i++) {
        expect(steps[i], greaterThan(0), reason: 'frame $i stalled');
      }
      // One glide, retargeted: a restart would show a step falling back to
      // a near-zero start after every fix.
      for (var fix = 1; fix < 6; fix++) {
        final at = fix * 6;
        expect(
          steps[at],
          greaterThan(steps[at - 1] * 0.5),
          reason: 'fix $fix restarted from rest',
        );
      }
      mapViewOf(fake).interrupt();
      await tester.pump(cameraEaseFrame);
    });

    testWidgets('a recenter flight lands in about half a second, smoothly', (
      tester,
    ) async {
      _stillClock();
      final fake = _FakeMap();
      final view = mapViewOf(fake)
        ..pose = const CameraPosition(target: _stockholm, zoom: 11.7);
      var done = false;
      unawaited(
        easeCameraTo(
          fake,
          CameraPosition(
            target: const LatLng(59.345, 18.09),
            zoom: 15,
            tilt: tiltForZoom(15),
          ),
          duration: cameraFlightDuration,
        ).then((_) => done = true),
      );
      await _frames(tester, done: () => done);
      expect(done, isTrue);
      final poses = fake.poses;
      // rider-cam-1: its length scales with the way (it was a fixed 1 s;
      // before that it crept on to the 240-frame cap, about 4-5 s).
      final length = flightDurationFor(
        const CameraPosition(target: _stockholm, zoom: 11.7),
        const CameraPosition(target: LatLng(59.345, 18.09), zoom: 15),
      );
      expect(length.inMilliseconds, inInclusiveRange(450, 600));
      final frames = length.inMicroseconds ~/ cameraEaseFrame.inMicroseconds;
      expect(poses.length, inInclusiveRange(frames - 2, frames + 2));
      final zooms = [for (final p in poses) _zoom(p)];
      for (var i = 1; i < zooms.length; i++) {
        expect(zooms[i], greaterThanOrEqualTo(zooms[i - 1]));
        expect(
          _tilt(poses[i]),
          closeTo(tiltForZoom(zooms[i]), 1e-6),
          reason: 'tilt rides with the zoom',
        );
      }
      final steps = [
        for (var i = 1; i < zooms.length; i++) zooms[i] - zooms[i - 1],
      ];
      final fastest = steps.reduce(math.max);
      // Three phases: the first and last steps run at 80 % of the middle
      // ones (owner), and the camera keeps moving right up to the goal.
      expect(steps[2], closeTo(fastest * slowPhaseSpeed, fastest * .05));
      expect(
        steps[steps.length - 4],
        closeTo(fastest * slowPhaseSpeed, fastest * .05),
      );
      expect(zooms.last, 15);
      expect(view.easing, isFalse);
    });

    test('a flight has three even phases, the first and last 20 % slower '
        'than the middle, joined without a cut', () {
      expect(flightEase(0), 0);
      expect(flightEase(1), 1);
      // Speed (progress per unit time) sampled finely.
      double speed(double t) =>
          (flightEase(t + .0005) - flightEase(t - .0005)) / .001;
      final slow = speed(.12), fast = speed(.5), end = speed(.88);
      expect(slow, closeTo(fast * slowPhaseSpeed, 1e-6));
      expect(end, closeTo(slow, 1e-6));
      // Even within each phase.
      for (final t in [.02, .1, .2]) {
        expect(speed(t), closeTo(slow, 1e-6));
      }
      for (final t in [.42, .5, .58]) {
        expect(speed(t), closeTo(fast, 1e-6));
      }
      for (final t in [.8, .9, .98]) {
        expect(speed(t), closeTo(end, 1e-6));
      }
      // The blends are smooth: the speed never jumps between samples.
      var previous = speed(.001);
      for (var i = 2; i < 999; i++) {
        final v = speed(i / 1000);
        expect((v - previous).abs(), lessThan(.01), reason: 't=${i / 1000}');
        previous = v;
      }
      // It leaves at once (no creep) and keeps moving until it lands.
      expect(speed(.001), greaterThan(.9));
      expect(speed(.999), greaterThan(.9));
    });

    testWidgets('a recenter that zooms in pans at an even speed on screen', (
      tester,
    ) async {
      _stillClock();
      final fake = _FakeMap();
      mapViewOf(fake).pose = const CameraPosition(
        target: _stockholm,
        zoom: 11.7,
      );
      var done = false;
      unawaited(
        easeCameraTo(
          fake,
          CameraPosition(
            target: const LatLng(59.345, 18.09),
            zoom: 15,
            tilt: tiltForZoom(15),
          ),
          duration: cameraFlightDuration,
        ).then((_) => done = true),
      );
      await _frames(tester, done: () => done);
      final poses = fake.poses;
      // A ground step looks 2^zoom times bigger on screen.
      final speeds = <double>[];
      for (var i = 1; i < poses.length; i++) {
        final a = _target(poses[i - 1]), b = _target(poses[i]);
        final ground = math.sqrt(
          math.pow(b[0] - a[0], 2) + math.pow(b[1] - a[1], 2),
        );
        speeds.add(ground * math.pow(2, _zoom(poses[i])));
      }
      // The even middle of the flight (between the ramps).
      final middle = speeds.sublist(
        (speeds.length * .3).round(),
        (speeds.length * .7).round(),
      );
      final ratio = middle.reduce(math.max) / middle.reduce(math.min);
      // It used to move 10x faster on screen at the end than at the start.
      expect(ratio, lessThan(1.6));
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

  group('rider-cam-1: a fast camera', () {
    /// [px] screen pixels east of [_stockholm] at [zoom].
    LatLng east(double px, double zoom) => LatLng(
      _stockholm.latitude,
      _stockholm.longitude + px / (256 * math.pow(2, zoom) / 360),
    );

    test('a flight takes as long as its way: hops ~300 ms, a recenter or fit '
        '~500-600 ms, never more than 700 ms', () {
      Duration flight(LatLng to, double fromZoom, double toZoom) =>
          flightDurationFor(
            CameraPosition(target: _stockholm, zoom: fromZoom),
            CameraPosition(target: to, zoom: toZoom),
          );
      final hop = flight(east(60, 15), 15, 15);
      expect(hop.inMilliseconds, inInclusiveRange(250, 350));
      expect(
        flight(east(150, 15), 15, 15).inMilliseconds,
        inInclusiveRange(300, 400),
      );
      // A recenter after the rider panned the map away, or a route fit.
      expect(
        flight(east(800, 14), 14, 15).inMilliseconds,
        inInclusiveRange(500, 600),
      );
      expect(
        flight(east(100, 11.7), 11.7, 15).inMilliseconds,
        inInclusiveRange(450, 600),
      );
      // Across the region: capped.
      expect(flight(east(20000, 15), 15, 10), cameraFlightDuration);
      expect(cameraFlightDuration.inMilliseconds, 700);
      // Longer the further it goes.
      var last = Duration.zero;
      for (final px in <double>[0, 20, 60, 150, 400, 1000, 3000, 10000]) {
        final d = flight(east(px, 15), 15, 15);
        expect(d, greaterThanOrEqualTo(last), reason: '$px px');
        expect(d.inMilliseconds, inInclusiveRange(250, 700));
        last = d;
      }
    });

    testWidgets('a short recenter lands in ~300 ms, on its goal', (
      tester,
    ) async {
      _stillClock();
      final fake = _FakeMap();
      mapViewOf(fake).pose = const CameraPosition(target: _stockholm, zoom: 15);
      final goal = CameraPosition(target: east(80, 15), zoom: 15);
      var done = false;
      unawaited(
        easeCameraTo(
          fake,
          goal,
          duration: cameraFlightDuration,
        ).then((_) => done = true),
      );
      await _frames(tester, done: () => done);
      expect(fake.poses.length, inInclusiveRange(15, 22));
      expect(_target(fake.poses.last), [
        goal.target.latitude,
        goal.target.longitude,
      ]);
    });

    testWidgets('a goal the camera already shows moves nothing', (
      tester,
    ) async {
      _stillClock();
      final flights = <CameraPosition>[];
      RiderMapBridge.debugFlight = (_, to, _) {
        flights.add(to);
        return Future.value(true);
      };
      addTearDown(() => RiderMapBridge.debugFlight = null);
      final fake = _FakeMap();
      final view = mapViewOf(fake)
        ..pose = const CameraPosition(target: _stockholm, zoom: 15);
      // Half a pixel away, a hair of zoom and heading: the same on screen.
      final same = CameraPosition(
        target: east(.5, 15),
        zoom: 15.001,
        bearing: .1,
      );
      final generation = view.generation;
      await easeCameraTo(fake, same, duration: cameraFlightDuration);
      await easeCameraTo(fake, same);
      view.mapId = 1;
      await easeCameraTo(fake, same, duration: cameraFlightDuration);
      expect(fake.calls, isEmpty);
      expect(flights, isEmpty);
      expect(view.easing, isFalse);
      expect(view.generation, generation, reason: 'nothing was interrupted');
      // Three pixels away is a move.
      view.mapId = null;
      unawaited(
        easeCameraTo(fake, CameraPosition(target: east(3, 15), zoom: 15)),
      );
      await _frames(tester, limit: 30);
      expect(fake.calls, isNotEmpty);
    });

    testWidgets('a follow glide settles well under 1 s, zoom and heading '
        'with the pan, exactly on its goal', (tester) async {
      _stillClock();
      final fake = _FakeMap();
      final view = mapViewOf(fake)
        ..tiltWithZoom = false
        ..pose = const CameraPosition(target: _stockholm, zoom: 14);
      final goal = CameraPosition(target: east(300, 15), zoom: 15, bearing: 30);
      var done = false;
      unawaited(easeCameraTo(fake, goal).then((_) => done = true));
      await _frames(tester, done: () => done);
      expect(done, isTrue);
      final poses = fake.poses;
      // It crept on for 2-3 s (time constants of 315-720 ms and settle
      // thresholds far below a pixel).
      expect(poses.length * 16, lessThan(700), reason: 'ms to settle');
      expect(poses.last['bearing'], 30);
      expect(_zoom(poses.last), 15);
      expect(_target(poses.last), [
        goal.target.latitude,
        goal.target.longitude,
      ]);
      // Halfway through, zoom and heading are as far along as the pan.
      final mid = poses[poses.length ~/ 2];
      final pan =
          (_target(mid)[1] - _stockholm.longitude) /
          (goal.target.longitude - _stockholm.longitude);
      expect(_zoom(mid) - 14, greaterThan(.5));
      expect((mid['bearing']! as num) / 30, greaterThan(.5));
      expect(pan, greaterThan(.5));
      // It leaves gently: the first frame is a small part of its fastest.
      final lngs = [for (final p in poses) _target(p)[1]];
      final steps = [
        lngs[0] - _stockholm.longitude,
        for (var i = 1; i < lngs.length; i++) lngs[i] - lngs[i - 1],
      ];
      expect(steps.first, lessThan(steps.reduce(math.max) * .5));
      expect(view.easing, isFalse);
    });

    testWidgets('on the web the follow glide runs on the browser frame clock; '
        'newer goals retarget it and a finger stops it', (tester) async {
      final glides = <(CameraPosition, Duration)>[];
      final landing = Completer<bool>();
      RiderMapBridge.debugGlide = (_, to, duration) {
        glides.add((to, duration));
        return landing.future;
      };
      const midway = CameraPosition(target: LatLng(59.331, 18.06), zoom: 13);
      RiderMapBridge.debugCancelFlight = (_) => midway;
      addTearDown(() {
        RiderMapBridge.debugGlide = null;
        RiderMapBridge.debugCancelFlight = null;
      });
      final fake = _FakeMap();
      final view = mapViewOf(fake)
        ..mapId = 1
        ..pose = const CameraPosition(target: _stockholm, zoom: 13);
      const first = CameraPosition(target: LatLng(59.332, 18.06), zoom: 13);
      const second = CameraPosition(target: LatLng(59.334, 18.06), zoom: 13);
      unawaited(easeCameraTo(fake, first));
      await tester.pump(cameraEaseFrame);
      expect(glides.single.$1, first);
      expect(glides.single.$2, cameraEaseDuration);
      expect(fake.calls, isEmpty, reason: 'no Dart timer steps on the web');
      expect(view.easing, isTrue);
      // The trip map refits: the same glide turns to the newer goal.
      unawaited(easeCameraTo(fake, second));
      expect(glides, hasLength(1));
      // A finger stops it where it is.
      view.touching = true;
      expect(view.pose, midway);
      expect(view.easing, isFalse);
      view.touching = false;
      // Landing: the goal becomes the pose, and late echoes are ignored.
      glides.clear();
      unawaited(easeCameraTo(fake, second));
      landing.complete(true);
      await tester.pump(cameraEaseFrame);
      expect(glides.single.$1, second);
      expect(view.pose, second);
      expect(view.easing, isFalse);
      expect(view.isLateEcho(midway), isTrue);
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
        CameraPosition(
          target: _stockholm,
          zoom: toZoom,
          bearing: 20,
          tilt: tilt,
        ),
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

    testWidgets('rider-j8-12: the rider\'s own move right after a web flight '
        'lands becomes the pose; only flight echoes are dropped', (
      tester,
    ) async {
      MapView.now = () => DateTime(2026);
      RiderMapBridge.debugFlight = (_, _, _) => Future.value(true);
      addTearDown(() => RiderMapBridge.debugFlight = null);
      final (fake, map) = await pumpMap(tester);
      final view = mapViewOf(fake)
        ..mapId = 1
        ..pose = const CameraPosition(target: _stockholm, zoom: 13);
      const goal = CameraPosition(target: LatLng(59.34, 18.07), zoom: 15);
      const far = CameraPosition(target: LatLng(59.4, 18.2), zoom: 15);
      Future<void> land() async {
        await easeCameraTo(fake, goal, duration: cameraFlightDuration);
        expect(view.pose, goal);
        expect(view.isLateEcho(far), isTrue, reason: 'a flight echo');
      }

      await land();
      final (a, b) = await pinch(tester, map, 16);
      await b.up();
      await a.up();
      expect(view.pose!.zoom, 16, reason: 'the pinch is the new pose');
      await land();
      view.movedByHandAt = MapView.now(); // A wheel zoom: no finger.
      expect(view.isLateEcho(far), isFalse);
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
