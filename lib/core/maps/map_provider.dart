import 'package:movera_rider/core/maps/geo_point.dart';

/// Map SDK is behind this. Screens never call Google Maps directly.
abstract class MapProvider {
  Future<void> moveCamera(GeoPoint target, {double zoom = 15});

  /// [follow]: an automatic update (a new position, a late fix). It leaves
  /// a map the rider is holding or has just moved alone. Without it the
  /// move is the rider's own request (recenter) and takes the map back.
  Future<void> animateCamera(
    GeoPoint target, {
    double zoom = 15,
    double bearing = 0,
    bool follow = false,
  });
  Future<void> fitBounds(
    GeoPoint a,
    GeoPoint b, {
    double padding = 56,
    bool follow = false,
  });
  void upsertMarker(String id, GeoPoint point, {double heading = 0});
  void removeMarker(String id);
  void drawRoute(String id, List<GeoPoint> points);
  void clearRoute(String id);
  void dispose();
}
