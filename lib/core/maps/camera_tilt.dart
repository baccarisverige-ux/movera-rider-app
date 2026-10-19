import 'dart:math' as math;

import 'package:google_maps_flutter/google_maps_flutter.dart';

/// The steepest tilt Google Maps accepts anywhere (vector JS maps and the
/// native SDKs both top out at 67.5°).
const double maxMapTilt = 67.5;

/// Zoom at which the tilt starts (flat at or below) and the zoom from which
/// the camera is fully tilted towards the horizon.
const double tiltStartZoom = 11;
const double tiltFullZoom = 15;

/// The steepest tilt the map engine allows at [zoom]. The native SDKs cap
/// the tilt by zoom (45° around zoom 10 rising to 67.5° from about 15.5);
/// asking for more makes the engine clamp it, so the camera would land
/// somewhere other than requested and visibly correct itself. Staying inside
/// this envelope means every requested pose is the pose drawn.
double maxTiltForZoom(double zoom) {
  if (!zoom.isFinite) return 0;
  if (zoom >= 15.5) return maxMapTilt;
  if (zoom <= 10) return 45;
  return 45 + (maxMapTilt - 45) * (zoom - 10) / 5.5;
}

/// Camera tilt for [zoom]: flat when zoomed out, leaning towards the horizon
/// as the rider zooms in, like a navigation app.
///
/// `T · s²(3 − 2s)` with `s = clamp((zoom − 11) / 4, 0, 1)` and T the
/// steepest accepted tilt, then kept inside [maxTiltForZoom].
double tiltForZoom(double zoom) {
  if (!zoom.isFinite) return 0;
  final s = ((zoom - tiltStartZoom) / (tiltFullZoom - tiltStartZoom)).clamp(
    0.0,
    1.0,
  );
  final eased = maxMapTilt * s * s * (3 - 2 * s);
  return math.min(eased, maxTiltForZoom(zoom));
}

/// [position] with the tilt that belongs to its zoom (target, zoom and
/// bearing unchanged).
CameraPosition withZoomTilt(CameraPosition position) => CameraPosition(
  target: position.target,
  zoom: position.zoom,
  bearing: position.bearing,
  tilt: tiltForZoom(position.zoom),
);

/// Whether [position]'s tilt is off from its zoom's tilt by more than
/// [toleranceDegrees], i.e. worth easing.
bool tiltNeedsEasing(CameraPosition position, {double toleranceDegrees = 1}) =>
    (position.tilt - tiltForZoom(position.zoom)).abs() > toleranceDegrees;

double _mercatorY(double latitude) {
  final lat = latitude.clamp(-85.05112878, 85.05112878) * math.pi / 180;
  return (1 - math.log(math.tan(lat) + 1 / math.cos(lat)) / math.pi) / 2;
}

double _latitudeForMercatorY(double y) {
  final n = math.pi * (1 - 2 * y);
  return math.atan((math.exp(n) - math.exp(-n)) / 2) * 180 / math.pi;
}

/// The flat (untilted) camera that `newLatLngBounds(bounds, padding)` would
/// produce on a map viewport of [width] × [height] logical pixels, with the
/// tilt for its zoom applied, so a fit is a single smooth camera move
/// instead of a flat fit followed by a second tilt move.
///
/// Tilting magnifies the near half of the view, so the zoom backs off a
/// little in proportion to the tilt to keep both framed points on screen.
/// With [tilted] false the pose is the plain flat fit.
/// Null when the viewport is too small to fit anything.
CameraPosition? tiltedFitCamera({
  required LatLng southwest,
  required LatLng northeast,
  required double width,
  required double height,
  double padding = 0,
  double maxZoom = 21,
  bool tilted = true,
}) {
  final w = width - 2 * padding;
  final h = height - 2 * padding;
  if (!(w > 1 && h > 1)) return null;
  final x1 = (southwest.longitude + 180) / 360;
  var x2 = (northeast.longitude + 180) / 360;
  if (x2 < x1) x2 += 1; // Bounds across the antimeridian.
  final yTop = _mercatorY(northeast.latitude);
  final yBottom = _mercatorY(southwest.latitude);
  final dx = (x2 - x1).abs();
  final dy = (yBottom - yTop).abs();
  double zoom;
  if (dx < 1e-12 && dy < 1e-12) {
    zoom = maxZoom;
  } else {
    final zx = dx < 1e-12 ? maxZoom : math.log(w / (256 * dx)) / math.ln2;
    final zy = dy < 1e-12 ? maxZoom : math.log(h / (256 * dy)) / math.ln2;
    zoom = math.min(math.min(zx, zy), maxZoom);
  }
  if (tilted) zoom -= 0.5 * tiltForZoom(zoom) / maxMapTilt;
  var cx = (x1 + x2) / 2;
  if (cx > 1) cx -= 1;
  final target = LatLng(
    _latitudeForMercatorY((yTop + yBottom) / 2),
    cx * 360 - 180,
  );
  return CameraPosition(
    target: target,
    zoom: zoom,
    tilt: tilted ? tiltForZoom(zoom) : 0,
  );
}

/// Shortest-way bearing interpolation in degrees.
double _lerpBearing(double a, double b, double t) {
  var d = (b - a) % 360;
  if (d > 180) d -= 360;
  if (d < -180) d += 360;
  return (a + d * t) % 360;
}

/// The pose a fraction [t] (0..1) of the way from [from] to [to].
CameraPosition lerpCamera(CameraPosition from, CameraPosition to, double t) {
  double lerp(double a, double b) => a + (b - a) * t;
  return CameraPosition(
    target: LatLng(
      lerp(from.target.latitude, to.target.latitude),
      lerp(from.target.longitude, to.target.longitude),
    ),
    zoom: lerp(from.zoom, to.zoom),
    tilt: lerp(from.tilt, to.tilt),
    bearing: _lerpBearing(from.bearing, to.bearing, t),
  );
}

/// Smooth start and stop for a camera ease.
double easeInOutCamera(double t) {
  final c = t.clamp(0.0, 1.0);
  return c * c * (3 - 2 * c);
}
