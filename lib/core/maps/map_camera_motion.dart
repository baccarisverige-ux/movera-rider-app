import 'dart:async';
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/core/maps/camera_tilt.dart';

/// What the app knows about one live map: its viewport, where its camera
/// is, and whether it leans with zoom.
class MapView {
  /// Map viewport in logical pixels, inside the map's own padding.
  Size? size;

  /// Last camera pose the map reported (or that this app set).
  CameraPosition? pose;

  /// False for screens that read a ground point from a screen-centred pin
  /// with flat-map maths (Set pickup, Confirm pickup spot): they stay flat.
  bool tiltWithZoom = true;

  /// False where the engine ignores tilt (raster maps on the web): the
  /// camera keeps the plain bounds fit there.
  bool supportsTilt = true;

  /// Bumped by every camera command. A stepped ease stops as soon as a newer
  /// command arrives, so an older pose never lands after a newer one.
  int generation = 0;

  /// True while a stepped (web) ease is running.
  bool easing = false;

  /// Tilt for [zoom] on this map (0 where it stays flat).
  double tiltFor(double zoom) =>
      tiltWithZoom && supportsTilt ? tiltForZoom(zoom) : 0;
}

final Expando<MapView> _views = Expando<MapView>('MapView');

/// The [MapView] of [controller], created on first use.
MapView mapViewOf(GoogleMapController controller) =>
    _views[controller] ??= MapView();

/// Native maps animate the camera themselves; on the web the plugin applies
/// zoom and tilt at once, so [easeCameraTo] steps the pose there instead.
@visibleForTesting
bool? debugSteppedCameraEase;

bool get _stepped => debugSteppedCameraEase ?? kIsWeb;

/// How long a camera ease takes.
const Duration cameraEaseDuration = Duration(milliseconds: 450);

/// Interval between the poses of a stepped ease (about 60 fps).
const Duration cameraEaseFrame = Duration(milliseconds: 16);

/// Moves [controller]'s camera to [to] continuously: one native camera
/// animation on phones; on the web a run of small poses eased in and out,
/// because the web plugin would otherwise snap zoom and tilt.
Future<void> easeCameraTo(
  GoogleMapController controller,
  CameraPosition to, {
  Duration duration = cameraEaseDuration,
}) async {
  final view = mapViewOf(controller);
  final generation = ++view.generation;
  if (!_stepped) {
    view.pose = to;
    await controller.animateCamera(
      CameraUpdate.newCameraPosition(to),
      duration: duration,
    );
    return;
  }
  final from = view.pose;
  if (from == null) {
    view.pose = to;
    await controller.moveCamera(CameraUpdate.newCameraPosition(to));
    return;
  }
  final frames = (duration.inMicroseconds / cameraEaseFrame.inMicroseconds)
      .ceil()
      .clamp(1, 240);
  view.easing = true;
  try {
    for (var i = 1; i <= frames; i++) {
      await Future<void>.delayed(cameraEaseFrame);
      if (view.generation != generation) return;
      final pose = lerpCamera(from, to, easeInOutCamera(i / frames));
      view.pose = pose;
      await controller.moveCamera(CameraUpdate.newCameraPosition(pose));
    }
  } finally {
    if (view.generation == generation) view.easing = false;
  }
}

/// Places [controller]'s camera at [to] immediately (no animation), and
/// stops any ease still running on it.
Future<void> placeCameraAt(GoogleMapController controller, CameraPosition to) {
  final view = mapViewOf(controller);
  view.generation += 1;
  view.easing = false;
  view.pose = to;
  return controller.moveCamera(CameraUpdate.newCameraPosition(to));
}

/// Runs a camera command the app cannot express as a pose (a plain bounds
/// fit), after stopping any ease still running on [controller].
Future<void> runCameraUpdate(
  GoogleMapController controller,
  CameraUpdate update,
) {
  final view = mapViewOf(controller);
  view.generation += 1;
  view.easing = false;
  return controller.animateCamera(update);
}
