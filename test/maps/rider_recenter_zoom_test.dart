// Owner 2026-10-31: "Make Max zoom in rider app exact exact like this", then
// "I meant with localisation botton ! But with two finger he can zoom !!".
// The location (recenter) button flies to zoom 13.8, the zoom measured from
// the owner's iPhone screenshot; the rider's own fingers still zoom closer.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/core/maps/camera_tilt.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/maps/google_map_provider.dart';
import 'package:movera_rider/core/maps/map_camera_controller.dart';
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

  Map<String, Object?> get lastPose =>
      (updates.last[1] as Map<Object?, Object?>).cast<String, Object?>();
}

void main() {
  test(
    'the location button flies to zoom 13.8 with that zoom\'s tilt',
    () async {
      final maps = GoogleMapProvider();
      final fake = _FakeMap();
      maps.attach(fake, owner: 'home');
      await MapCameraController(
        maps,
      ).followUser(const GeoPoint(59.1937, 17.5994));
      expect(fake.updates.last.first, 'newCameraPosition');
      expect(fake.lastPose['zoom'], 13.8);
      expect(
        (fake.lastPose['tilt']! as num).toDouble(),
        closeTo(tiltForZoom(13.8), 1e-9),
      );
    },
  );

  test('other camera moves are not capped at the button\'s zoom', () async {
    final maps = GoogleMapProvider();
    final fake = _FakeMap();
    maps.attach(fake, owner: 'home');
    await maps.animateCamera(const GeoPoint(59.1937, 17.5994), zoom: 16.4);
    expect(fake.lastPose['zoom'], 16.4);
  });

  testWidgets('two fingers may zoom past 13.8: the map sets no zoom cap', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CustomGoogleMap(
            initialPosition: CameraPosition(
              target: LatLng(59.1937, 17.5994),
              zoom: 16.4,
            ),
          ),
        ),
      ),
    );
    final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
    expect(map.minMaxZoomPreference.maxZoom, isNull);
    expect(map.initialCameraPosition.zoom, 16.4);
  });
}
