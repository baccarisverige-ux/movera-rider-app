import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/shared/widgets/movera_map_markers.dart';

/// uat-r2 (owner, real iPhone): the location puck looked blurred because it
/// was painted at 1x and stretched on a 3x screen.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the pin is painted at 3x by default and tells the map its pixel '
      'ratio', () async {
    final visual = await MoveraRiderPuckMarker.createVisual();
    final logical = MoveraRiderPuckMarker.geometry(0).size;
    expect(visual.image.width, (logical.width * 3).ceil());
    expect(visual.image.height, (logical.height * 3).ceil());
    final icon = visual.icon as BytesMapBitmap;
    expect(icon.imagePixelRatio, markerPixelRatio);
    visual.image.dispose();
  });

  Future<ui.Image> decode(BitmapDescriptor icon) async {
    final codec = await ui.instantiateImageCodec(
      (icon as BytesMapBitmap).byteData,
    );
    return (await codec.getNextFrame()).image;
  }

  test('the car and the route pins are painted at 3x too', () async {
    final car = await decode(await MoveraVehicleMarker.createIcon());
    expect(car.width, (48 * 0.65 * 3).round());
    final pin = await decode(
      await RouteEndpointMarker.createIcon(pickup: true),
    );
    expect(pin.width, 90);
  });
}
