import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/home/presentation/home.dart';

/// Home opens on the whole local area around the rider (the Södertälje
/// screenshot): about 10 km across a 402 pt wide phone, at zoom ≈ 11.7.
void main() {
  test('the opening zoom frames ~10 km across a 402 pt phone', () {
    expect(homeOpeningZoom, 11.7);
    // Web Mercator: metres per logical pixel at Södertälje (59.2° N).
    final metresPerPoint =
        156543.03392 *
        math.cos(59.2 * math.pi / 180) /
        math.pow(2, homeOpeningZoom);
    final acrossKm = metresPerPoint * 402 / 1000;
    expect(acrossKm, inInclusiveRange(9, 11));
  });

  test('Home uses the opening zoom before and after the first fix', () {
    final src = File(
      'lib/features/home/presentation/home.dart',
    ).readAsStringSync();
    // Initial camera, the quick cached fix, the accurate first fix and the
    // map-created catch-up all open at the same zoom.
    expect('zoom: homeOpeningZoom'.allMatches(src).length, 4);
    // The rider's own "recenter" keeps its close street zoom.
    expect(src.contains('zoom: 17,'), isTrue);
  });
}
