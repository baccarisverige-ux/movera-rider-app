// Owner 2026-10-31 ("Make Max zoom in rider app exact exact like this"):
// the closest any rider map goes is zoom 13.8, the zoom measured from the
// owner's iPhone screenshot of rider Home in Södertälje. These tests drive
// the real camera code and the real map widget and check where the camera
// ends up.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/core/maps/camera_tilt.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/maps/google_map_provider.dart';
import 'package:movera_rider/core/maps/map_camera_controller.dart';
import 'package:movera_rider/core/maps/map_camera_motion.dart';
import 'package:movera_rider/shared/widgets/custom_google_map.dart';

/// Records camera commands instead of driving a platform map.
class _FakeMap extends Fake implements GoogleMapController {
  final List<List<dynamic>> updates = [];

  @override
  Future<void> animateCamera(CameraUpdate cameraUpdate, {Duration? duration}) {
    updates.add(cameraUpdate.toJson() as List<dynamic>);
    return Future<void>.value();
  }

  @override
  Future<void> moveCamera(CameraUpdate cameraUpdate) {
    updates.add(cameraUpdate.toJson() as List<dynamic>);
    return Future<void>.value();
  }

  @override
  Future<String?> getStyleError() async => null;

  List<Map<String, Object?>> get poses => [
    for (final update in updates)
      if (update.first == 'newCameraPosition')
        (update[1] as Map<Object?, Object?>).cast<String, Object?>(),
  ];

  /// Every zoom the map was sent: poses and zoom updates alike.
  List<double> get zooms => [
    for (final pose in poses) (pose['zoom']! as num).toDouble(),
    for (final update in updates)
      if (update.first == 'newLatLngZoom') (update[2] as num).toDouble(),
  ];
}

double _zoom(Map<String, Object?> pose) => (pose['zoom']! as num).toDouble();
double _tilt(Map<String, Object?> pose) => (pose['tilt']! as num).toDouble();

const _sodertalje = LatLng(59.1937, 17.5994);

void main() {
  tearDown(() => MapView.now = DateTime.now);

  test('the rider max zoom is the measured 13.8', () {
    expect(riderMaxZoom, 13.8);
    expect(riderZoomPreference.maxZoom, 13.8);
    expect(riderZoomPreference.minZoom, isNull);
    // Recenter and route fits go exactly as close as the cap, no closer.
    expect(recenterZoom, riderMaxZoom);
    expect(routeFitMaxZoom, riderMaxZoom);
  });

  group('capping a camera', () {
    test('zooms at or below the cap are kept as they are', () {
      expect(capRiderZoom(11.7), 11.7);
      expect(capRiderZoom(13.8), 13.8);
      const pose = CameraPosition(
        target: _sodertalje,
        zoom: 13,
        tilt: 10,
        bearing: 30,
      );
      expect(capRiderCamera(pose), same(pose));
    });

    test('a closer zoom lands on the cap, with the cap\'s tilt', () {
      expect(capRiderZoom(16.2), 13.8);
      final capped = capRiderCamera(
        CameraPosition(
          target: _sodertalje,
          zoom: 17,
          tilt: tiltForZoom(17),
          bearing: 40,
        ),
      );
      expect(capped.zoom, 13.8);
      expect(capped.tilt, closeTo(tiltForZoom(13.8), 1e-9));
      expect(capped.bearing, 40);
      expect(capped.target, _sodertalje);
    });

    test('a flat (pickup pin) map stays flat when capped', () {
      final capped = capRiderCamera(
        const CameraPosition(target: _sodertalje, zoom: 16.4),
      );
      expect(capped.zoom, 13.8);
      expect(capped.tilt, 0);
    });
  });

  test('a route fit of two close points stops at the cap', () {
    final pose = tiltedFitCamera(
      southwest: const LatLng(59.1937, 17.5994),
      northeast: const LatLng(59.1938, 17.5995),
      width: 402,
      height: 812,
      padding: 56,
    )!;
    expect(pose.zoom, lessThanOrEqualTo(13.8));
  });

  group('every camera command the app sends', () {
    late GoogleMapProvider maps;
    late _FakeMap fake;

    setUp(() {
      MapView.now = () => DateTime(2026);
      maps = GoogleMapProvider();
      fake = _FakeMap();
      maps.attach(fake, owner: 'home');
    });

    test('a move asked closer than the cap lands on the cap', () async {
      await maps.moveCamera(const GeoPoint(59.1937, 17.5994), zoom: 18);
      expect(_zoom(fake.poses.single), 13.8);
      expect(_tilt(fake.poses.single), closeTo(tiltForZoom(13.8), 1e-9));
    });

    test('recenter flies to the cap and then hides the button', () async {
      final camera = MapCameraController(maps);
      await camera.followUser(const GeoPoint(59.1937, 17.5994));
      expect(_zoom(fake.poses.single), 13.8);
      expect(camera.showRecenter(zoom: 13.8, metersFromUser: 0), isFalse);
      expect(camera.showRecenter(zoom: 12, metersFromUser: 0), isTrue);
    });

    testWidgets('a flight from afar never passes the cap on any frame', (
      tester,
    ) async {
      mapViewOf(fake).pose = const CameraPosition(
        target: LatLng(59.33, 18.06),
        zoom: 11.7,
      );
      var done = false;
      maps
          .animateCamera(const GeoPoint(59.1937, 17.5994), zoom: 17)
          .then((_) => done = true);
      for (var i = 0; i < 400 && !done; i++) {
        await tester.pump(cameraEaseFrame);
      }
      expect(done, isTrue);
      expect(fake.zooms, isNotEmpty);
      expect(fake.zooms.every((z) => z <= 13.8), isTrue);
      expect(_zoom(fake.poses.last), 13.8);
    });

    test('a fit of two close points stops at the cap', () async {
      await maps.fitBounds(
        const GeoPoint(59.1937, 17.5994),
        const GeoPoint(59.19371, 17.59941),
      );
      expect(fake.zooms, isNotEmpty);
      expect(fake.zooms.every((z) => z <= 13.8), isTrue);
    });

    test('a fit on a known viewport stops at the cap, with its tilt', () async {
      mapViewOf(fake).size = const Size(402, 812);
      await maps.fitBounds(
        const GeoPoint(59.1937, 17.5994),
        const GeoPoint(59.19371, 17.59941),
      );
      final pose = fake.poses.single;
      expect(_zoom(pose), lessThanOrEqualTo(13.8));
      expect(_tilt(pose), closeTo(tiltForZoom(_zoom(pose)), 1e-9));
    });
  });

  group('the map widget', () {
    testWidgets('pinch and double tap stop at the cap', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: CustomGoogleMap())),
      );
      final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
      expect(map.minMaxZoomPreference.maxZoom, 13.8);
    });

    testWidgets('a screen asking to open closer opens at the cap', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CustomGoogleMap(
              initialPosition: CameraPosition(target: _sodertalje, zoom: 16.4),
            ),
          ),
        ),
      );
      final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
      expect(map.initialCameraPosition.zoom, 13.8);
      expect(map.initialCameraPosition.target, _sodertalje);
    });
  });
}
