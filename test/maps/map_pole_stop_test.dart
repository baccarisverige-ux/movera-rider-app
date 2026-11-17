import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:movera_rider/core/maps/map_pole_limit.dart';
import 'package:movera_rider/core/maps/map_zoom_limit.dart';
import 'package:movera_rider/shared/widgets/custom_google_map.dart';

import '../fixtures/fake_maps_platform.dart';

/// Owner 2026-11-17 ("When slide map must stop with the arctic and
/// antarctic in north side and south side! Don't show that after."): no
/// grey band above or below the world, at any zoom.
void main() {
  const phone = Size(390, 844);

  CameraPosition at(double lat, double zoom, {double bearing = 0}) =>
      CameraPosition(target: LatLng(lat, 18), zoom: zoom, bearing: bearing);

  test('a view inside the world is left alone', () {
    expect(MapPoleLimit.clamp(at(59.33, 13), phone), isNull);
    expect(MapPoleLimit.clamp(at(59.33, kMapMinZoom), phone), isNull);
  });

  for (final zoom in [kMapMinZoom, 7.0, 10.0, 16.0]) {
    test('dragged to the North Pole at zoom $zoom: the top edge stops at '
        '85.05° N, the bottom at 85.05° S', () {
      for (final lat in [86.0, 89.9, -86.0, -89.9]) {
        for (final bearing in [0.0, 30.0, 180.0]) {
          final camera = at(lat, zoom, bearing: bearing);
          final stop = MapPoleLimit.clamp(camera, phone)!;
          final seen = MapPoleLimit.visibleLatitudes(stop, phone);
          expect(seen.north, lessThanOrEqualTo(kMapMaxLatitude + 1e-6));
          expect(seen.south, greaterThanOrEqualTo(-kMapMaxLatitude - 1e-6));
          // It stops on the edge, not short of it.
          expect(
            lat > 0 ? seen.north : -seen.south,
            closeTo(kMapMaxLatitude, 1e-3),
          );
          expect(stop.zoom, zoom);
          expect(stop.bearing, bearing);
          expect(stop.target.longitude, 18);
          // The stop is a resting place: no second correction (no jitter).
          expect(MapPoleLimit.clamp(stop, phone), isNull);
        }
      }
    });
  }

  test('zoomed in, the centre may go further north', () {
    final far = MapPoleLimit.clamp(at(89, kMapMinZoom), phone)!;
    final near = MapPoleLimit.clamp(at(89, 10), phone)!;
    expect(near.target.latitude, greaterThan(far.target.latitude));
  });

  testWidgets('phones: a drag past the Arctic puts the camera back on the '
      'edge', (tester) async {
    final maps = GoogleMapsFlutterPlatform.instance;
    final fake = FakeMapsPlatform();
    GoogleMapsFlutterPlatform.instance = fake;
    CustomGoogleMap.debugWaitForMaps = false;
    addTearDown(() {
      GoogleMapsFlutterPlatform.instance = maps;
      CustomGoogleMap.debugWaitForMaps = null;
    });
    // Pole stops: camera moves the app sends that are not a tilt ease.
    List<CameraPosition> stops() => [
      for (final sent in fake.cameraUpdates)
        if (sent.update.toJson() case ['newCameraPosition', final Object? json])
          CameraPosition.fromMap(json)!,
    ].where((c) => c.target.latitude.abs() > 80).toList();
    tester.view.physicalSize = phone;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: CustomGoogleMap())),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final id = fake.createdIds.last;
    final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
    // Phones: no centre lock (it would not stop the view, only the centre).
    expect(map.cameraTargetBounds, CameraTargetBounds.unbounded);

    for (final zoom in [kMapMinZoom, 10.0]) {
      fake.cameraUpdates.clear();
      fake.emit(CameraMoveEvent(id, at(88, zoom)));
      await tester.pump();
      expect(stops(), hasLength(1), reason: 'zoom $zoom');
      final camera = stops().single;
      final seen = MapPoleLimit.visibleLatitudes(camera, phone);
      expect(seen.north, lessThanOrEqualTo(kMapMaxLatitude + 1e-6));
      expect(seen.north, closeTo(kMapMaxLatitude, 1e-3));
      // The echo of the stop, and the idle after it, send nothing more.
      fake.emit(CameraMoveEvent(id, camera));
      fake.emit(CameraIdleEvent(id));
      await tester.pump(const Duration(seconds: 1));
      expect(stops(), hasLength(1));
    }
    // Inside the world: nothing is sent.
    fake.cameraUpdates.clear();
    fake.emit(CameraMoveEvent(id, at(59.33, 13)));
    await tester.pump();
    expect(stops(), isEmpty);
  });
}
