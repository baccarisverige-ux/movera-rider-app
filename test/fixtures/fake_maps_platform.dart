import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformViewCreatedCallback;
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

/// A maps platform that creates its view at once, so `onMapCreated` fires
/// and the widget holds a controller with a map id, as it does in the
/// browser. Nothing else is simulated.
class FakeMapsPlatform extends GoogleMapsFlutterPlatform {
  FakeMapsPlatform({this.createsView = true});

  /// False: the view never comes up (a browser without the Maps script),
  /// so the widget never gets a controller.
  final bool createsView;
  final List<int> disposed = <int>[];
  final Set<int> _created = <int>{};

  /// The configuration of the last view built (traffic layer, gestures…).
  MapConfiguration? lastConfiguration;
  final StreamController<MapEvent<Object?>> _events =
      StreamController<MapEvent<Object?>>.broadcast();

  /// Sends [event] as the plugin would (a camera report, for example).
  void emit(MapEvent<Object?> event) => _events.add(event);

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
    lastConfiguration = mapConfiguration;
    // A view is created once, however often its widget rebuilds.
    if (createsView && _created.add(creationId)) {
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
  Future<void> updateMarkers(
    MarkerUpdates markerUpdates, {
    required int mapId,
  }) async {}

  @override
  Future<void> updatePolygons(
    PolygonUpdates polygonUpdates, {
    required int mapId,
  }) async {}

  @override
  Future<void> updatePolylines(
    PolylineUpdates polylineUpdates, {
    required int mapId,
  }) async {}

  @override
  Future<void> updateCircles(
    CircleUpdates circleUpdates, {
    required int mapId,
  }) async {}

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
  Future<void> updateHeatmaps(
    HeatmapUpdates heatmapUpdates, {
    required int mapId,
  }) async {}

  @override
  Future<void> updateGroundOverlays(
    GroundOverlayUpdates groundOverlayUpdates, {
    required int mapId,
  }) async {}

  @override
  Future<String?> getStyleError({required int mapId}) async => null;

  @override
  Future<void> animateCamera(
    CameraUpdate cameraUpdate, {
    required int mapId,
  }) async {}

  @override
  Future<void> moveCamera(
    CameraUpdate cameraUpdate, {
    required int mapId,
  }) async {}

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
