import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart'
    show GoogleMapsFlutterPlatform;
import 'package:movera_rider/core/maps/map_zoom_limit.dart';
import 'package:movera_rider/features/history/presentation/past_ride_route_map.dart';
import 'package:movera_rider/shared/widgets/custom_google_map.dart';

import '../fixtures/fake_maps_platform.dart';

/// Owner 2026-11-17 ("Make Max zoom out like that not all planet"; both
/// apps, fixed): no map zooms out wider than Scandinavia + Baltic on a
/// phone (zoom 4.5). A zoom level, not a region lock.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GoogleMapsFlutterPlatform previousPlatform;

  setUp(() {
    previousPlatform = GoogleMapsFlutterPlatform.instance;
    GoogleMapsFlutterPlatform.instance = FakeMapsPlatform();
    CustomGoogleMap.debugWaitForMaps = false;
  });

  tearDown(() {
    GoogleMapsFlutterPlatform.instance = previousPlatform;
    CustomGoogleMap.debugWaitForMaps = null;
  });

  test('the limit is zoom 4.5, never the planet', () {
    expect(kMapMinZoom, 4.5);
    expect(clampMapZoom(1), kMapMinZoom);
    expect(clampMapZoom(13), 13);
  });

  testWidgets('every map is built with the zoom-out limit, panning free', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: CustomGoogleMap())),
    );
    await tester.pump();
    final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
    expect(map.minMaxZoomPreference.minZoom, kMapMinZoom);
    expect(map.minMaxZoomPreference.maxZoom, isNull);
    expect(map.cameraTargetBounds, CameraTargetBounds.unbounded);
  });

  test('a fit to two far-apart points clamps to the limit', () {
    // Stockholm to Tunis, and Stockholm to Sydney: both would need wider.
    final europe = LatLngBounds(
      southwest: const LatLng(36.8, 10.18),
      northeast: const LatLng(59.33, 18.07),
    );
    final planet = LatLngBounds(
      southwest: const LatLng(-33.87, 18.07),
      northeast: const LatLng(59.33, 151.2),
    );
    expect(pastRideFitZoom(europe), kMapMinZoom);
    expect(pastRideFitZoom(planet), kMapMinZoom);
  });
}
