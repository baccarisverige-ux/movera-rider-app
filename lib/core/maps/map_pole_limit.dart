import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Owner 2026-11-17 ("When slide map must stop with the arctic and
/// antarctic in north side and south side! Don't show that after."; both
/// apps, fixed): the map ends at the top and bottom of the world. Google's
/// Web Mercator map stops at about 85.05° north and south; past it there is
/// only an empty grey band, so no screen may show past it, at any zoom.
/// East-west panning stays free (the world wraps).
const double kMapMaxLatitude = 85.05112877980659;

/// The vertical pan stop for one camera on one map size. The centre may go
/// further north the closer the map is zoomed in and the shorter the map
/// is, so the stop is computed from the view, not a fixed latitude.
abstract final class MapPoleLimit {
  /// Google Maps draws the world 256 logical pixels wide at zoom 0.
  static const double _tile = 256;

  /// 0 at the top of the world (85.05° N), 1 at the bottom.
  static double _worldY(double latitude) {
    final lat = latitude.clamp(-kMapMaxLatitude, kMapMaxLatitude);
    final sin = math.sin(lat * math.pi / 180);
    return .5 - math.log((1 + sin) / (1 - sin)) / (4 * math.pi);
  }

  static double _latitude(double worldY) {
    final n = math.pi - 2 * math.pi * worldY;
    return 180 / math.pi * math.atan(0.5 * (math.exp(n) - math.exp(-n)));
  }

  /// How far the view reaches north and south of the camera target, in
  /// logical pixels along the map's north-south axis. The target sits in
  /// the middle of the map less its [padding]; a turned map ([bearing])
  /// reaches further with its corners.
  static ({double north, double south}) _reach(
    CameraPosition camera,
    Size size,
    EdgeInsets padding,
  ) {
    final up = (size.height + padding.top - padding.bottom) / 2;
    final down = (size.height - padding.top + padding.bottom) / 2;
    final left = (size.width + padding.left - padding.right) / 2;
    final right = (size.width - padding.left + padding.right) / 2;
    final b = camera.bearing * math.pi / 180;
    final cos = math.cos(b), sin = math.sin(b);
    var north = 0.0, south = 0.0;
    for (final x in [-left, right]) {
      for (final y in [-up, down]) {
        // Screen y grows downwards; turned by the bearing onto the map.
        final worldDy = y * cos - x * sin;
        north = math.max(north, -worldDy);
        south = math.max(south, worldDy);
      }
    }
    return (north: north, south: south);
  }

  /// The latitudes of the top and bottom edges the view shows.
  static ({double north, double south}) visibleLatitudes(
    CameraPosition camera,
    Size size, {
    EdgeInsets padding = EdgeInsets.zero,
  }) {
    final world = _tile * math.pow(2, camera.zoom);
    final reach = _reach(camera, size, padding);
    final y = _worldY(camera.target.latitude) * world;
    return (
      north: _latitude((y - reach.north) / world),
      south: _latitude((y + reach.south) / world),
    );
  }

  /// The camera moved back so its view ends at the world's top or bottom
  /// edge, or null when the view is already inside the world. Zoom,
  /// bearing, tilt and longitude are kept.
  static CameraPosition? clamp(
    CameraPosition camera,
    Size size, {
    EdgeInsets padding = EdgeInsets.zero,
  }) {
    if (size.isEmpty || !camera.zoom.isFinite) return null;
    final world = _tile * math.pow(2, camera.zoom);
    final reach = _reach(camera, size, padding);
    final y = _worldY(camera.target.latitude) * world;
    final double wanted;
    if (reach.north + reach.south >= world) {
      // Taller than the world (not reached at the min zoom 4.5 on a
      // phone): keep the world centred between the edges.
      wanted = world / 2 + (reach.north - reach.south) / 2;
    } else {
      wanted = y.clamp(reach.north, world - reach.south);
    }
    if ((wanted - y).abs() < 1e-6) return null;
    return CameraPosition(
      target: LatLng(_latitude(wanted / world), camera.target.longitude),
      zoom: camera.zoom,
      bearing: camera.bearing,
      tilt: camera.tilt,
    );
  }
}
