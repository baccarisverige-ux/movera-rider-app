import 'package:movera_rider/core/web/rider_map_bridge_io.dart'
    if (dart.library.js_interop) 'package:movera_rider/core/web/rider_map_bridge_web.dart'
    as impl;

/// The web gesture layer (web/rider_map_camera.js) of one Google map: the
/// rider's pinch and wheel zoom carry the tilt along on every frame, and an
/// app camera step lands at once. Every call is a no-op off the web or
/// before Maps JavaScript and the layer are installed.
abstract final class RiderMapBridge {
  /// Whether the map draws tilt (a vector map); null while unknown (the
  /// layer is not installed or Google has not picked a renderer yet).
  /// Phones always do.
  static bool? supports3D(int mapId) => impl.supports3D(mapId);

  /// Which of the rider's own gestures the layer performs.
  static void gestures(
    int mapId, {
    required bool scroll,
    required bool zoom,
    required bool rotate,
    required bool tilt,
  }) => impl.gestures(mapId, scroll, zoom, rotate, tilt);

  /// The rider's own zoom carries the tilt along (off on flat pin maps).
  static void tiltFollowsZoom(int mapId, bool enabled) =>
      impl.tiltFollowsZoom(mapId, enabled);

  /// [onGesture] runs whenever the rider moves the map by hand.
  static void Function() listen(int mapId, void Function() onGesture) =>
      impl.listen(mapId, onGesture);

  /// The next camera position the app sends lands at once (no glide).
  static void claim(int mapId) => impl.claim(mapId);
}
