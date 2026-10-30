import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/shared/widgets/movera_map_markers.dart';

/// Owner decision (rider map, 2026-10-30): the rider's position dot is
/// Movera blue (dot, cone and halo); the white ring around it stays.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<({int r, int g, int b, int a})> Function(double, double) reader(
    ui.Image image,
  ) {
    const scale = 0.588 * MoveraRiderPuckMarker.pixelRatio;
    return (double x, double y) async {
      final data = (await image.toByteData())!;
      final px = (x * scale).round();
      final py = (y * scale).round();
      final i = (py * image.width + px) * 4;
      return (
        r: data.getUint8(i),
        g: data.getUint8(i + 1),
        b: data.getUint8(i + 2),
        a: data.getUint8(i + 3),
      );
    };
  }

  for (final expanded in [false, true]) {
    test(
      'the puck dot, cone and halo are blue (expanded: $expanded)',
      () async {
        final visual = await MoveraRiderPuckMarker.createVisual(
          expanded: expanded,
        );
        final at = reader(visual.image);

        // The dot: Movera blue.
        final dot = await at(56, 84);
        const blue = MoveraRiderPuckMarker.riderPuckBlue;
        expect(dot.a, 255);
        expect(dot.r, closeTo((blue.r * 255).round(), 2));
        expect(dot.g, closeTo((blue.g * 255).round(), 2));
        expect(dot.b, closeTo((blue.b * 255).round(), 2));
        expect(dot.b - dot.r, greaterThan(100), reason: 'not grey');

        // The white ring stays.
        final ring = await at(56 + 17.5, 84);
        expect(ring, (r: 255, g: 255, b: 255, a: 255));

        // The halo outside the ring and the cone above the dot are tinted
        // blue too (premultiplied, translucent).
        final halo = await at(56 + 23, 84);
        expect(halo.a, greaterThan(0));
        expect(halo.b - halo.r, greaterThan(halo.a ~/ 3), reason: 'halo');
        final cone = await at(56, 40);
        expect(cone.a, greaterThan(0));
        expect(cone.b - cone.r, greaterThan(cone.a ~/ 3), reason: 'cone');
        visual.image.dispose();
      },
    );
  }
}
