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

  /// The map's element grew: Google measures it again and draws the new
  /// area (web/rider_map_camera.js). A no-op off the web.
  static void redraw(int mapId) => impl.redraw(mapId);

  /// Owner 2026-10-31 (rider-pin SPEC): the grey accuracy halo under the
  /// rider's pin, drawn by the web layer on [mapId]: a flat circle at
  /// [center], [accuracyMeters] in radius but kept [minRadius]..[maxRadius]
  /// points on screen, re-clamped on the same frame as every zoom step so
  /// it never lags a pinch. A null [center] removes it. A no-op off the web
  /// (phones draw a [Circle]).
  static void halo(
    int mapId, {
    required LatLng? center,
    double? accuracyMeters,
    double minRadius = 60,
    double maxRadius = 110,
    String color = '#7797A8',
    double opacity = 0.35,
  }) {
    final fake = debugHalo;
    if (fake != null) {
      fake(mapId, center, accuracyMeters);
      return;
    }
    impl.halo(
      mapId,
      center?.latitude,
      center?.longitude,
      accuracyMeters,
      minRadius,
      maxRadius,
      color,
      opacity,
    );
  }

  /// Tests stand in for the web layer's [halo].
  @visibleForTesting
  static void Function(int mapId, LatLng? center, double? accuracyMeters)?
  debugHalo;

  /// The widget of this map is gone. google.maps.Map has no destroy(): the
  /// Maps script and google_maps_flutter_web both keep every map for the
  /// life of the page, so a map Flutter had removed kept its tiles,
  /// listeners and (vector maps) its WebGL context: 5-6 maps a booking, and
  /// Safari evicts the oldest WebGL contexts (often Flutter's own) past
  /// about 16 a page. The layer takes the map back for the next screen
  /// once Flutter has removed its element (web/rider_map_camera.js). A
  /// no-op off the web.
  static void release(int mapId) {
    final fake = debugRelease;
    if (fake != null) {
      fake(mapId);
      return;
    }
    impl.release(mapId);
  }

  /// Tests stand in for the web layer's [release].
  @visibleForTesting
  static void Function(int mapId)? debugRelease;

  /// Whether a disposed map's id is wanted by [release]: on the web, and in
  /// a test standing in for the layer. Phone tests hand in bare fakes
  /// without an id.
  static bool get wantsRelease => kIsWeb || debugRelease != null;

  /// Live web maps, Google maps really created and taken back for another
  /// screen, maps waiting in the layer's pool, maps gutted beyond it and
  /// WebGL contexts given back since the page loaded; null off the web (or
  /// before the layer is there).
  static ({
    int live,
    int created,
    int recycled,
    int pooled,
    int released,
    int contextsReleased,
  })?
  stats() => impl.stats();

  /// Flies the camera to [to] over [duration] on the browser's frame clock
  /// (one camera move per painted frame, the flight ease of
  /// map_camera_motion.dart). Completes with true when it lands, false when
  /// cancelled; null when the layer is not there (the Dart loop steps).
  static Future<bool>? flight(int mapId, CameraPosition to, Duration duration) {
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
