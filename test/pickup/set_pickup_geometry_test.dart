import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/features/pickup/presentation/set_pickup_page.dart';

/// The pickup is the point under the pin, a third of the way down the
/// screen, computed from the camera centre with map maths on every platform.
void main() {
  const centre = LatLng(59.2390, 17.8450);

  test('the pickup sits north of the camera centre by the pin offset', () {
    final pickup = setPickupPointAbove(centre, 16.2, 136);
    expect(pickup.longitude, centre.longitude);
    // ~136 px at zoom 16.2 near Stockholm is roughly 140 m north.
    final metres = (pickup.latitude - centre.latitude) * 111320;
    expect(metres, inInclusiveRange(120, 160));
  });

  test('camera and pickup conversions are inverses', () {
    final pickup = setPickupPointAbove(centre, 16.2, 136);
    final back = setPickupCameraFor(pickup, 16.2, 136);
    expect(back.latitude, closeTo(centre.latitude, 1e-7));
    expect(back.longitude, centre.longitude);
  });

  test('zooming out moves the pickup further for the same pixels', () {
    final near =
        setPickupPointAbove(centre, 17, 136).latitude - centre.latitude;
    final far = setPickupPointAbove(centre, 14, 136).latitude - centre.latitude;
    expect(far / near, closeTo(8, 0.01));
  });
}
