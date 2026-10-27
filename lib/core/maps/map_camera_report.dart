import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Which camera reports are camera frames (owner N6, audit phase 6).
///
/// google_maps_flutter_web (0.5.14+2, `convert.dart`
/// `_gmViewportToCameraPosition`) builds every `onCameraMove` report from
/// Maps JavaScript's getters and puts **0** where Maps has no value yet:
/// zoom 0 when the zoom is undefined, the centre (0, 0) when the centre
/// is. No rider map shows zoom 0 (the web gesture layer keeps a pinch in
/// 3–21) nor the Gulf of Guinea, so such a report is a gap, not a frame.
/// Taken for one it became the camera's pose, the origin of the next app
/// ease (a recenter or route fit then flew in from a world view), and the
/// zoom the pickup pin's ground maths read. The driver app drops the same
/// reports (driver #380, `MapCameraReport`).
abstract final class MapCameraReport {
  /// True when [position] carries a zoom and a centre.
  static bool isFrame(CameraPosition position) {
    if (!position.zoom.isFinite || position.zoom <= 0) return false;
    final target = position.target;
    if (!target.latitude.isFinite || !target.longitude.isFinite) return false;
    return target.latitude != 0 || target.longitude != 0;
  }
}
