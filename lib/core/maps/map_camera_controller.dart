import 'package:movera_rider/core/location/location_repository.dart';
import 'package:movera_rider/core/maps/camera_mode.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/maps/google_map_provider.dart';
import 'package:movera_rider/core/utils/stale_guard.dart';

/// Zoom the location (recenter) button flies to on every rider map (owner,
/// 2026-10-31: "I meant with localisation botton ! But with two finger he
/// can zoom !!"). Measured from the owner's iPhone screenshot of rider Home
/// in Södertälje: zoom 13.8, tilted ~35° by the zoom's tilt curve. Only the
/// button (and the locate glide it starts) uses it; pinch, double tap and
/// wheel still zoom in further.
const double recenterZoom = 13.8;

class MapCameraController {
  MapCameraController(this._maps, {LocationRepository? location})
    : _location = location ?? LocationRepository();
  final GoogleMapProvider _maps;
  final LocationRepository _location;
  final stale = StaleGuard();

  /// The map is off the rider: zoomed well out of [recenterZoom], or moved
  /// away. A recentred map ([recenterZoom]) hides the button.
  bool showRecenter({required double zoom, required double metersFromUser}) {
    return zoom < recenterZoom - 0.5 || metersFromUser > 35;
  }

  bool followOrFree({
    required double zoom,
    required GeoPoint cameraTarget,
    required GeoPoint user,
  }) {
    final meters = _location.distanceBetween(
      cameraTarget.latitude,
      cameraTarget.longitude,
      user.latitude,
      user.longitude,
    );
    final free = showRecenter(zoom: zoom, metersFromUser: meters);
    _maps.mode = free ? CameraMode.free : CameraMode.followUser;
    return free;
  }

  Future<void> focusOnPickup(GeoPoint point) {
    _maps.mode = CameraMode.pickupSelection;
    return _maps.animateCamera(point, zoom: recenterZoom);
  }

  Future<void> followUser(GeoPoint point) {
    final gen = stale.next();
    _maps.mode = CameraMode.followUser;
    return _run(gen, () => _maps.animateCamera(point, zoom: recenterZoom));
  }

  Future<void> _run(int gen, Future<void> Function() action) async {
    await action();
    if (!stale.isCurrent(gen)) return;
  }
}
