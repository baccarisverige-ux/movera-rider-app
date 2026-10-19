import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/core/maps/camera_tilt.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/maps/google_map_provider.dart';
import 'package:movera_rider/core/maps/map_camera_motion.dart';
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

void main() {
  tearDown(() => debugSteppedCameraEase = null);

  group('tiltForZoom', () {
    test('flat when zoomed out, full horizon lean from zoom 15', () {
      expect(tiltForZoom(8), 0);
      expect(tiltForZoom(11), 0);
      expect(tiltForZoom(12), closeTo(10.55, 0.01));
      expect(tiltForZoom(13), closeTo(33.75, 0.01));
      expect(tiltForZoom(14), closeTo(56.95, 0.01));
      // At 15 the curve asks for 67.5° but the engine allows ~65.5° there.
      expect(tiltForZoom(15), closeTo(maxTiltForZoom(15), 1e-9));
      expect(tiltForZoom(15.5), maxMapTilt);
      expect(tiltForZoom(17), maxMapTilt);
      expect(tiltForZoom(21), maxMapTilt);
      expect(tiltForZoom(double.nan), 0);
    });

    test('never above what the engine accepts, and continuous', () {
      var previous = tiltForZoom(5);
      var biggestStep = 0.0;
      for (var z = 5.0; z <= 22; z += 0.01) {
        final t = tiltForZoom(z);
        expect(t, lessThanOrEqualTo(maxTiltForZoom(z) + 1e-9), reason: '$z');
        expect(t, lessThanOrEqualTo(maxMapTilt));
        expect(t, greaterThanOrEqualTo(previous - 1e-9), reason: '$z');
        final step = (t - previous).abs();
        if (step > biggestStep) biggestStep = step;
        previous = t;
      }
      // No jump: at most ~0.26° of tilt per 0.01 zoom anywhere.
      expect(biggestStep, lessThan(0.3));
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

    test('animate at zoom 17 leans fully, at zoom 11 stays flat', () async {
      await maps.animateCamera(const GeoPoint(59.33, 18.06), zoom: 17);
      expect(_tilt(fake.poses.last), maxMapTilt);
      await maps.animateCamera(const GeoPoint(59.33, 18.06), zoom: 11);
      expect(_tilt(fake.poses.last), 0);
      await maps.animateCamera(const GeoPoint(59.33, 18.06), zoom: 13);
      expect(_tilt(fake.poses.last), closeTo(33.75, 0.01));
      expect(fake.calls.every((c) => c.$1 == 'animate'), isTrue);
    });

    test('move carries the zoom tilt too', () async {
      await maps.moveCamera(const GeoPoint(59.33, 18.06), zoom: 16);
      expect(fake.calls.single.$1, 'move');
      expect(_tilt(fake.poses.single), maxMapTilt);
    });

    test('Home opening zoom 11.7 is nearly flat', () {
      expect(tiltForZoom(11.7), lessThan(6));
    });

    test('a whole-route fit is flat, a close fit leans, in one move', () async {
      mapViewOf(fake).size = const Size(390, 700);
      // Stockholm → Arlanda: an overview, zoom ~10.
      await maps.fitBounds(
        const GeoPoint(59.3293, 18.0686),
        const GeoPoint(59.6519, 17.9186),
      );
      expect(fake.calls, hasLength(1));
      expect(_zoom(fake.poses.single), lessThan(11));
      expect(_tilt(fake.poses.single), 0);

      fake.calls.clear();
      // Driver ~300 m from the pickup: a close fit.
      await maps.fitBounds(
        const GeoPoint(59.3293, 18.0686),
        const GeoPoint(59.3313, 18.0716),
      );
      expect(fake.calls, hasLength(1));
      final pose = fake.poses.single;
      expect(_zoom(pose), greaterThan(14));
      expect(_tilt(pose), closeTo(tiltForZoom(_zoom(pose)), 1e-9));
      expect(_tilt(pose), greaterThan(50));
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

  group('stepped (web) ease', () {
    testWidgets('glides with small steps and never jumps', (tester) async {
      await _steppedEase(tester, (fake, view, elapse) async {
        view.pose = const CameraPosition(
          target: LatLng(59.33, 18.06),
          zoom: 13,
        );
        easeCameraTo(
          fake,
          const CameraPosition(
            target: LatLng(59.331, 18.061),
            zoom: 16,
            tilt: maxMapTilt,
          ),
        );
        await elapse(const Duration(seconds: 1));
        final poses = fake.poses;
        expect(poses.length, greaterThan(20));
        var lastTilt = 0.0, lastZoom = 13.0, maxTiltStep = 0.0;
        var maxZoomStep = 0.0;
        for (final pose in poses) {
          final t = _tilt(pose), z = _zoom(pose);
          expect(t, greaterThanOrEqualTo(lastTilt));
          expect(z, greaterThanOrEqualTo(lastZoom));
          maxTiltStep = [
            maxTiltStep,
            t - lastTilt,
          ].reduce((a, b) => a > b ? a : b);
          maxZoomStep = [
            maxZoomStep,
            z - lastZoom,
          ].reduce((a, b) => a > b ? a : b);
          lastTilt = t;
          lastZoom = z;
        }
        expect(lastTilt, maxMapTilt);
        expect(lastZoom, 16);
        // 29 frames over 450 ms: the biggest per-frame step is ~1/19 of the
        // way (smoothstep peak 1.5 / 29 frames).
        expect(maxTiltStep, lessThan(4));
        expect(maxZoomStep, lessThan(0.2));
      });
    });

    testWidgets('a newer move wins: no older pose lands after it', (
      tester,
    ) async {
      await _steppedEase(tester, (fake, view, elapse) async {
        view.pose = const CameraPosition(
          target: LatLng(59.33, 18.06),
          zoom: 13,
        );
        easeCameraTo(
          fake,
          const CameraPosition(
            target: LatLng(59.33, 18.06),
            zoom: 17,
            tilt: 60,
          ),
        );
        await elapse(const Duration(milliseconds: 100));
        final before = fake.poses.length;
        easeCameraTo(
          fake,
          const CameraPosition(target: LatLng(59.33, 18.06), zoom: 11),
        );
        await elapse(const Duration(seconds: 1));
        final after = fake.poses.sublist(before);
        // Everything after the second command heads to zoom 11: the zoom only
        // goes down from where the first ease was stopped.
        var last = double.infinity;
        for (final pose in after) {
          expect(_zoom(pose), lessThanOrEqualTo(last));
          last = _zoom(pose);
        }
        expect(_zoom(fake.poses.last), 11);
        expect(_tilt(fake.poses.last), 0);
      });
    });
  });

  group('pinch release on CustomGoogleMap', () {
    Future<(_FakeMap, GoogleMap)> pumpMap(
      WidgetTester tester, {
      bool tiltWithZoom = true,
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

    void pinch(GoogleMap map, double fromZoom, double toZoom, double tilt) {
      map.onCameraMoveStarted!();
      map.onCameraMove!(
        CameraPosition(
          target: const LatLng(59.33, 18.06),
          zoom: (fromZoom + toZoom) / 2,
          tilt: tilt,
        ),
      );
      map.onCameraMove!(
        CameraPosition(
          target: const LatLng(59.33, 18.06),
          zoom: toZoom,
          bearing: 20,
          tilt: tilt,
        ),
      );
      map.onCameraIdle!();
    }

    testWidgets('zooming in and letting go eases the tilt in', (tester) async {
      final (fake, map) = await pumpMap(tester);
      // The viewport is known to the provider for fits.
      expect(mapViewOf(fake).size, const Size(390, 500));
      pinch(map, 13, 16.5, 0);
      final pose = fake.poses.single;
      expect(fake.calls.single.$1, 'animate');
      expect(_tilt(pose), maxMapTilt);
      expect(_zoom(pose), 16.5);
      expect(pose['bearing'], 20);
      expect(_target(pose), [59.33, 18.06]);
    });

    testWidgets('zooming out flattens', (tester) async {
      final (fake, map) = await pumpMap(tester);
      mapViewOf(fake).pose = const CameraPosition(
        target: LatLng(59.33, 18.06),
        zoom: 16,
        tilt: maxMapTilt,
      );
      pinch(map, 16, 10.5, maxMapTilt);
      expect(_tilt(fake.poses.single), 0);
    });

    testWidgets('a finger still down waits; lifting it eases', (tester) async {
      final (fake, map) = await pumpMap(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(GoogleMap)),
      );
      pinch(map, 13, 16, 0);
      expect(fake.calls, isEmpty);
      await gesture.up();
      expect(_tilt(fake.poses.single), maxMapTilt);
    });

    testWidgets('a pan keeps the pose', (tester) async {
      final (fake, map) = await pumpMap(tester);
      pinch(map, 13, 13, 0);
      expect(fake.calls, isEmpty);
    });

    testWidgets('a flat map (pickup pin screens) is never tilted', (
      tester,
    ) async {
      final (fake, map) = await pumpMap(tester, tiltWithZoom: false);
      pinch(map, 13, 17, 0);
      expect(fake.calls, isEmpty);
      expect(mapViewOf(fake).tiltWithZoom, isFalse);
    });
  });
}

/// Runs [body] with the stepped (web) ease on the test clock.
Future<void> _steppedEase(
  WidgetTester tester,
  Future<void> Function(
    _FakeMap fake,
    MapView view,
    Future<void> Function(Duration) elapse,
  )
  body,
) async {
  debugSteppedCameraEase = true;
  final fake = _FakeMap();
  await body(fake, mapViewOf(fake), (total) async {
    for (var t = Duration.zero; t < total; t += cameraEaseFrame) {
      await tester.pump(cameraEaseFrame);
    }
  });
}
