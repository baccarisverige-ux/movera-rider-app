import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
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

  /// Flies the camera to [to] over [duration] on the browser's frame clock
  /// (one camera move per painted frame, the flight ease of
  /// map_camera_motion.dart). Completes with true when it lands, false when
  /// cancelled; null when the layer is not there (the Dart loop steps).
  static Future<bool>? flight(
    int mapId,
    CameraPosition to,
    Duration duration,
  ) {
    final fake = debugFlight;
    if (fake != null) return fake(mapId, to, duration);
    return impl.flight(
      mapId,
      to.target.latitude,
      to.target.longitude,
      to.zoom,
      to.bearing,
      to.tilt,
      duration.inMilliseconds,
    );
  }

  /// Tests stand in for the web layer's [flight] (off the web there is none).
  @visibleForTesting
  static Future<bool>? Function(
    int mapId,
    CameraPosition to,
    Duration duration,
  )?
  debugFlight;

  /// Glides the camera to [to] on the browser's frame clock: the follow
  /// glide of map_camera_motion.dart ([duration] is its span), one camera
  /// move per painted frame. Completes with true when it lands, false when
  /// cancelled; null when the layer is not there (the Dart loop steps).
  static Future<bool>? glide(int mapId, CameraPosition to, Duration duration) {
    final fake = debugGlide;
    if (fake != null) return fake(mapId, to, duration);
    return impl.glide(
      mapId,
      to.target.latitude,
      to.target.longitude,
      to.zoom,
      to.bearing,
      to.tilt,
      duration.inMilliseconds,
    );
  }

  /// Tests stand in for the web layer's [glide].
  @visibleForTesting
  static Future<bool>? Function(
    int mapId,
    CameraPosition to,
    Duration duration,
  )?
  debugGlide;

  /// A running flight or glide turns towards [to]: a flight on its own
  /// clock, a glide at the speed it has.
  static void retarget(int mapId, CameraPosition to) => impl.retarget(
        mapId,
        to.target.latitude,
        to.target.longitude,
        to.zoom,
        to.bearing,
        to.tilt,
      );

  /// Stops a running flight or glide where it is, and returns where that
  /// is (null when nothing was moving or the layer cannot tell).
  static CameraPosition? cancelFlight(int mapId) {
    final fake = debugCancelFlight;
    if (fake != null) return fake(mapId);
    final at = impl.cancelFlight(mapId);
    if (at == null) return null;
    return CameraPosition(
      target: LatLng(at.lat, at.lng),
      zoom: at.zoom,
      bearing: at.heading,
      tilt: at.tilt,
    );
  }

  /// Tests stand in for the web layer's [cancelFlight].
  @visibleForTesting
  static CameraPosition? Function(int mapId)? debugCancelFlight;
}
