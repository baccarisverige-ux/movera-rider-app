part of 'waiting_for_driver.dart';

/// D-016: how long the driver marker eases towards a new fix. Following the
/// actual interval between fixes (clamped) removes the move-then-stall rhythm
/// a fixed short ease produced at a 2–3 s fix cadence.
@visibleForTesting
Duration driverEaseDuration(Duration? sinceLastFix) {
  const fallback = Duration(milliseconds: 900);
  const shortest = Duration(milliseconds: 400);
  const longest = Duration(milliseconds: 4000);
  if (sinceLastFix == null || sinceLastFix <= Duration.zero) return fallback;
  if (sinceLastFix < shortest) return shortest;
  if (sinceLastFix > longest) return longest;
  return sinceLastFix;
}

/// rider-u58: whether the driver car eases between fixes. On web every
/// marker update makes google_maps_flutter_web convert the car icon to a
/// new blob URL that is never revoked, so a ~20 fps ease for the whole
/// trip leaked thousands of blobs an hour; there the car moves once per
/// fix instead. Native platforms keep the D-016 ease.
@visibleForTesting
bool driverMarkerEases = !kIsWeb;

/// D-018: bounds and uniform padding that frame [a] and [b] above a bottom
/// obstruction (the sheet) instead of padding every side by its height.
///
/// google_maps_flutter 2.13 only offers a single uniform padding for
/// `newLatLngBounds`, so the obstruction is reserved by stretching the bounds
/// southwards: the real points then land in the top
/// `viewportHeight - bottomObstruction` of the map.
@visibleForTesting
({GeoPoint southwest, GeoPoint northeast, double padding}) waitingCameraFit({
  required GeoPoint a,
  required GeoPoint b,
  required double viewportHeight,
  required double bottomObstruction,
  double edgePadding = 48,
}) {
  const minSpan = 0.002; // ~200 m, so driver-at-pickup doesn't zoom to max.
  var south = math.min(a.latitude, b.latitude);
  var north = math.max(a.latitude, b.latitude);
  var west = math.min(a.longitude, b.longitude);
  var east = math.max(a.longitude, b.longitude);
  if (north - south < minSpan) {
    final mid = (north + south) / 2;
    south = mid - minSpan / 2;
    north = mid + minSpan / 2;
  }
  if (east - west < minSpan) {
    final mid = (east + west) / 2;
    west = mid - minSpan / 2;
    east = mid + minSpan / 2;
  }
  final full = math.max(viewportHeight - 2 * edgePadding, 1.0);
  final usable = math.max(
    viewportHeight - bottomObstruction - 2 * edgePadding,
    full * 0.25,
  );
  final span = north - south;
  final stretchedSouth = north - span * (full / usable);
  return (
    southwest: GeoPoint(math.max(stretchedSouth, -85.0), west),
    northeast: GeoPoint(north, east),
    padding: edgePadding,
  );
}
