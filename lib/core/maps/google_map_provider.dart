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

  /// Tests: told about every [moveCamera] / [animateCamera] request and the
  /// owner it would move, before the active map is checked.
  @visibleForTesting
  void Function(String? owner, GeoPoint target)? debugOnCameraCommand;

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

  /// Whether a camera command may run on [map] now. An automatic
  /// ([follow]) update leaves a map the rider holds or just moved alone; a
  /// requested one takes it back.
  bool _mayMove(GoogleMapController map, bool follow) {
    final view = mapViewOf(map);
    if (follow) return !view.heldByRider;
    if (view.touching) return false;
    view.movedByHandAt = null;
    return true;
  }

  @override
  Future<void> moveCamera(GeoPoint target, {double zoom = 15}) async {
    debugOnCameraCommand?.call(activeOwner, target);
    final map = controller;
    if (map == null || !_mayMove(map, true)) return;
    await placeCameraAt(map, _pose(target, zoom, 0));
  }

  @override
  Future<void> animateCamera(
    GeoPoint target, {
    double zoom = 15,
    double bearing = 0,
    bool follow = false,
  }) async {
    debugOnCameraCommand?.call(activeOwner, target);
    final map = controller;
    if (map == null || !_mayMove(map, follow)) return;
    await easeCameraTo(
      map,
      _pose(target, zoom, bearing),
      duration: follow ? cameraEaseDuration : cameraFlightDuration,
    );
  }

  /// Frames both points. When the map's viewport is known the fit is one
  /// continuous move (a flight, or the follow glide when [follow]) to the fitted pose with its zoom's tilt (flat for wide
  /// route overviews, leaning for close ones); otherwise, and on maps that
  /// ignore tilt, it is the plain bounds fit.
  @override
  Future<void> fitBounds(
    GeoPoint a,
    GeoPoint b, {
    double padding = 56,
    bool follow = false,
  }) async {
    final map = controller;
    if (map == null || !_mayMove(map, follow)) return;
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
        // A requested fit (the route overview) is a flight that lands on
        // time; a follow refit (the trip map) glides.
        await easeCameraTo(
          map,
          fitted,
          duration: follow ? cameraEaseDuration : cameraFlightDuration,
        );
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
