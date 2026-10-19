import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/core/maps/camera_mode.dart';
import 'package:movera_rider/core/maps/camera_tilt.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/maps/map_camera_motion.dart';
import 'package:movera_rider/core/maps/map_provider.dart';
import 'package:movera_rider/core/maps/marker_store.dart';

class _OwnedMap {
  const _OwnedMap(this.owner, this.controller);
  final String owner;
  final GoogleMapController? controller;
}

class GoogleMapProvider implements MapProvider {
  final List<_OwnedMap> _owners = [];
  final MarkerStore markers = MarkerStore();
  final Map<String, List<GeoPoint>> routes = {};
  int generation = 0;
  CameraMode mode = CameraMode.followUser;
  void Function(String? owner, int generation)? onOwnerDebug;

  GoogleMapController? get controller =>
      _owners.isEmpty ? null : _owners.last.controller;

  String? get activeOwner => _owners.isEmpty ? null : _owners.last.owner;

  List<String> get ownerStack =>
      _owners.map((item) => item.owner).toList(growable: false);

  void attach(GoogleMapController controller, {String owner = 'map'}) {
    _push(owner, controller);
  }

  /// Test hook for owner/generation without a plugin controller.
  @visibleForTesting
  void debugAttach(String owner) => _push(owner, null);

  void _notifyOwner() => onOwnerDebug?.call(activeOwner, generation);

  void _push(String owner, GoogleMapController? controller) {
    generation += 1;
    _owners.removeWhere((item) => item.owner == owner);
    _owners.add(_OwnedMap(owner, controller));
    _notifyOwner();
  }

  /// Release this owner's controller wherever it sits in the stack.
  ///
  /// A background route can dispose after a newer map has become current.
  /// Keeping that stale owner underneath the live map lets its dead controller
  /// become active again when the newer map later detaches.
  void detach({String owner = 'map'}) {
    if (_owners.isEmpty) return;
    final activeBefore = activeOwner;
    final before = _owners.length;
    _owners.removeWhere((item) => item.owner == owner);
    if (_owners.length == before) return;
    if (activeOwner != activeBefore) _notifyOwner();
  }

  /// Camera pose for [target] at [zoom] on the active map, tilted for the
  /// zoom unless that map stays flat.
  CameraPosition _pose(GeoPoint target, double zoom, double bearing) {
    final map = controller;
    final tilt = map == null ? tiltForZoom(zoom) : mapViewOf(map).tiltFor(zoom);
    return CameraPosition(
      target: LatLng(target.latitude, target.longitude),
      zoom: zoom,
      bearing: bearing,
      tilt: tilt,
    );
  }

  @override
  Future<void> moveCamera(GeoPoint target, {double zoom = 15}) async {
    final map = controller;
    if (map == null) return;
    await placeCameraAt(map, _pose(target, zoom, 0));
  }

  @override
  Future<void> animateCamera(
    GeoPoint target, {
    double zoom = 15,
    double bearing = 0,
  }) async {
    final map = controller;
    if (map == null) return;
    await easeCameraTo(map, _pose(target, zoom, bearing));
  }

  /// Frames both points. When the map's viewport is known the fit is one
  /// continuous move to the fitted pose with its zoom's tilt (flat for wide
  /// route overviews, leaning for close ones); otherwise, and on maps that
  /// ignore tilt, it is the plain bounds fit.
  @override
  Future<void> fitBounds(GeoPoint a, GeoPoint b, {double padding = 56}) async {
    final map = controller;
    if (map == null) return;
    final southwest = LatLng(
      a.latitude < b.latitude ? a.latitude : b.latitude,
      a.longitude < b.longitude ? a.longitude : b.longitude,
    );
    final northeast = LatLng(
      a.latitude > b.latitude ? a.latitude : b.latitude,
      a.longitude > b.longitude ? a.longitude : b.longitude,
    );
    final view = mapViewOf(map);
    final size = view.size;
    if (size != null && view.supportsTilt) {
      final fitted = tiltedFitCamera(
        southwest: southwest,
        northeast: northeast,
        width: size.width,
        height: size.height,
        padding: padding,
        tilted: view.tiltWithZoom,
      );
      if (fitted != null) {
        await easeCameraTo(map, fitted);
        return;
      }
    }
    await runCameraUpdate(
      map,
      CameraUpdate.newLatLngBounds(
        LatLngBounds(southwest: southwest, northeast: northeast),
        padding,
      ),
    );
  }

  @override
  void upsertMarker(String id, GeoPoint point, {double heading = 0}) {
    markers.upsert(id, point, heading: heading);
  }

  @override
  void removeMarker(String id) => markers.remove(id);

  @override
  void drawRoute(String id, List<GeoPoint> points) => routes[id] = points;

  @override
  void clearRoute(String id) => routes.remove(id);

  @override
  void dispose() {
    // Never dispose plugin controllers. Drop ownership only.
    _owners.clear();
    _notifyOwner();
  }
}
