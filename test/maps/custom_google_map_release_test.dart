import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformViewCreatedCallback;
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:movera_rider/core/web/rider_map_bridge.dart';
import 'package:movera_rider/shared/widgets/custom_google_map.dart';

/// A maps platform that creates its view at once, so `onMapCreated` fires
/// and the widget holds a controller with a map id, as it does in the
/// browser. Nothing else is simulated.
class _FakeMapsPlatform extends GoogleMapsFlutterPlatform {
  _FakeMapsPlatform({this.createsView = true});

  /// False: the view never comes up (a browser without the Maps script),
  /// so the widget never gets a controller.
  final bool createsView;
  final List<int> disposed = <int>[];
  final StreamController<MapEvent<Object?>> _events =
      StreamController<MapEvent<Object?>>.broadcast();

  Stream<T> _of<T extends MapEvent<Object?>>(int mapId) =>
      _events.stream.where((e) => e is T && e.mapId == mapId).cast<T>();

  @override
  Future<void> init(int mapId) async {}

  @override
  Widget buildViewWithConfiguration(
    int creationId,
    PlatformViewCreatedCallback onPlatformViewCreated, {
    required MapWidgetConfiguration widgetConfiguration,
    MapConfiguration mapConfiguration = const MapConfiguration(),
    MapObjects mapObjects = const MapObjects(),
  }) {
    if (createsView) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => onPlatformViewCreated(creationId),
      );
    }
    return const SizedBox.expand();
  }

  @override
  void dispose({required int mapId}) => disposed.add(mapId);

  @override
  Future<void> updateMapConfiguration(
    MapConfiguration update, {
    required int mapId,
  }) async {}

  @override
  Future<void> updateMarkers(MarkerUpdates markerUpdates,
          {required int mapId}) async {}

  @override
  Future<void> updatePolygons(PolygonUpdates polygonUpdates,
          {required int mapId}) async {}

  @override
  Future<void> updatePolylines(PolylineUpdates polylineUpdates,
          {required int mapId}) async {}

  @override
  Future<void> updateCircles(CircleUpdates circleUpdates,
          {required int mapId}) async {}

  @override
  Future<void> updateTileOverlays({
    required Set<TileOverlay> newTileOverlays,
    required int mapId,
  }) async {}

  @override
  Future<void> updateClusterManagers(
    ClusterManagerUpdates clusterManagerUpdates, {
    required int mapId,
  }) async {}

  @override
  Future<void> updateHeatmaps(HeatmapUpdates heatmapUpdates,
          {required int mapId}) async {}

  @override
  Future<void> updateGroundOverlays(
    GroundOverlayUpdates groundOverlayUpdates, {
    required int mapId,
  }) async {}

  @override
  Future<String?> getStyleError({required int mapId}) async => null;

  @override
  Future<void> animateCamera(CameraUpdate cameraUpdate,
          {required int mapId}) async {}

  @override
  Future<void> moveCamera(CameraUpdate cameraUpdate,
          {required int mapId}) async {}

  @override
  Future<void> setMapStyle(String? mapStyle, {required int mapId}) async {}

  @override
  Future<double> getZoomLevel({required int mapId}) async => 14;

  @override
  Stream<CameraMoveStartedEvent> onCameraMoveStarted({required int mapId}) =>
      _of(mapId);
  @override
  Stream<CameraMoveEvent> onCameraMove({required int mapId}) => _of(mapId);
  @override
  Stream<CameraIdleEvent> onCameraIdle({required int mapId}) => _of(mapId);
  @override
  Stream<MarkerTapEvent> onMarkerTap({required int mapId}) => _of(mapId);
  @override
  Stream<InfoWindowTapEvent> onInfoWindowTap({required int mapId}) =>
      _of(mapId);
  @override
  Stream<MarkerDragStartEvent> onMarkerDragStart({required int mapId}) =>
      _of(mapId);
  @override
  Stream<MarkerDragEvent> onMarkerDrag({required int mapId}) => _of(mapId);
  @override
  Stream<MarkerDragEndEvent> onMarkerDragEnd({required int mapId}) =>
      _of(mapId);
  @override
  Stream<PolylineTapEvent> onPolylineTap({required int mapId}) => _of(mapId);
  @override
  Stream<PolygonTapEvent> onPolygonTap({required int mapId}) => _of(mapId);
  @override
  Stream<CircleTapEvent> onCircleTap({required int mapId}) => _of(mapId);
  @override
  Stream<MapTapEvent> onTap({required int mapId}) => _of(mapId);
  @override
  Stream<MapLongPressEvent> onLongPress({required int mapId}) => _of(mapId);
  @override
  Stream<ClusterTapEvent> onClusterTap({required int mapId}) => _of(mapId);
  @override
  Stream<GroundOverlayTapEvent> onGroundOverlayTap({required int mapId}) =>
      _of(mapId);
}

/// On the web every Google map Flutter removes lives on in the plugin's
/// platform view registry (google.maps.Map has no destroy()). The widget
/// therefore asks the web layer to release the map when it is disposed; the
/// layer gives back its tiles, listeners and WebGL context once the element
/// is out of the DOM (web/rider_map_camera.js, measured in
/// docs/web-lifecycle-investigation.md).
void main() {
  late _FakeMapsPlatform platform;
  late GoogleMapsFlutterPlatform previous;
  final released = <int>[];

  setUp(() {
    previous = GoogleMapsFlutterPlatform.instance;
    platform = _FakeMapsPlatform();
    GoogleMapsFlutterPlatform.instance = platform;
    released.clear();
    RiderMapBridge.debugRelease = released.add;
    CustomGoogleMap.debugWaitForMaps = false;
  });

  tearDown(() {
    RiderMapBridge.debugRelease = null;
    CustomGoogleMap.debugWaitForMaps = null;
    GoogleMapsFlutterPlatform.instance = previous;
  });

  testWidgets('a disposed map is released to the web layer by its map id', (
    tester,
  ) async {
    GoogleMapController? created;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomGoogleMap(
            key: const ValueKey('probe-map'),
            onMapCreated: (controller) => created = controller,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(created, isNotNull, reason: 'the fake platform creates the view');
    expect(released, isEmpty, reason: 'nothing is released while mounted');

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();

    expect(released, [created!.mapId]);
    expect(platform.disposed, [created!.mapId],
        reason: 'the plugin still disposes its own controller');
  });

  testWidgets('a map disposed before it was created releases nothing', (
    tester,
  ) async {
    // The platform never answers: no controller, no map id to release.
    GoogleMapsFlutterPlatform.instance = _FakeMapsPlatform(createsView: false);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: CustomGoogleMap())),
    );
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();
    expect(released, isEmpty);
  });

  testWidgets('every mount is recorded for the lifecycle tests', (
    tester,
  ) async {
    CustomGoogleMap.debugMounted.clear();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: CustomGoogleMap(key: ValueKey('first'))),
      ),
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: CustomGoogleMap(key: ValueKey('second'))),
      ),
    );
    expect(
      CustomGoogleMap.debugMounted,
      const [ValueKey('first'), ValueKey('second')],
    );
    CustomGoogleMap.debugMounted.clear();
  });
}
