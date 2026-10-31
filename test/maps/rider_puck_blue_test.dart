import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/shared/widgets/movera_map_markers.dart';

/// Owner 2026-10-31 (plan/rider-pin/SPEC.md): the rider's position pin is a
/// flat blue #008CFA dot about 9 pt across in a white ring about 1.5-2 pt,
/// with a very soft shadow; on a tilted map a white puck. Same size on
/// screen at every zoom. Grey #7797A8 halo at 35 %, no border.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<({int r, int g, int b, int a}) Function(double, double)> reader(
    ui.Image image,
    double ratio,
  ) async {
    final data = (await image.toByteData())!;
    return (double x, double y) {
      final px = (x * ratio).floor();
      final py = (y * ratio).floor();
      final i = (py * image.width + px) * 4;
      return (
        r: data.getUint8(i),
        g: data.getUint8(i + 1),
        b: data.getUint8(i + 2),
        a: data.getUint8(i + 3),
      );
    };
  }

  test('flat pin: solid #008CFA centre, white ring, soft shadow', () async {
    const ratio = 3.0;
    final visual = await MoveraRiderPuckMarker.createVisual(pixelRatio: ratio);
    final at = await reader(visual.image, ratio);
    final c = MoveraRiderPuckMarker.geometry(0).centre;

    // Blue centre, flat (the same colour across the dot).
    for (final dx in [-3.0, 0.0, 3.0]) {
      expect(at(c.dx + dx, c.dy), (r: 0, g: 140, b: 250, a: 255));
    }
    // Blue diameter about 9 pt: 4 pt out is blue, 5 pt out is not.
    expect(at(c.dx + 4.2, c.dy).b, 250);
    expect(at(c.dx + 4.2, c.dy).r, lessThan(40));
    // White ring between 4.5 and 6.25 pt.
    expect(at(c.dx + 5.4, c.dy), (r: 255, g: 255, b: 255, a: 255));
    expect(at(c.dx, c.dy - 5.4), (r: 255, g: 255, b: 255, a: 255));
    // Very soft shadow just outside the ring, transparent further out.
    final shadow = at(c.dx, c.dy + 7.2);
    expect(shadow.a, inInclusiveRange(1, 90));
    expect(at(1, 1).a, 0);
    visual.image.dispose();
  });

  test('ring width and dot size match the spec', () {
    expect(MoveraRiderPuckMarker.blue, const Color(0xFF008CFA));
    expect(MoveraRiderPuckMarker.dotDiameter, 9);
    expect(MoveraRiderPuckMarker.ringWidth, inInclusiveRange(1.5, 2));
    expect(MoveraRiderPuckMarker.flatDiameter, inInclusiveRange(12, 13));
  });

  test('tilted map: white puck with a blue ellipse and a grey wall', () async {
    const ratio = 3.0;
    const tilt = 60.0;
    final g = MoveraRiderPuckMarker.geometry(tilt);
    expect(g.top.width, MoveraRiderPuckMarker.puckWidth);
    expect(g.top.height, closeTo(11, 0.01));
    expect(g.dot.width, 16);
    expect(g.dot.height, closeTo(8.8, 0.01));
    expect(g.wall, 3);

    final visual = await MoveraRiderPuckMarker.createVisual(
      tilt: tilt,
      pixelRatio: ratio,
    );
    final at = await reader(visual.image, ratio);
    final c = g.centre;
    expect(at(c.dx, c.dy), (r: 0, g: 140, b: 250, a: 255));
    // The top's white rim beside the blue ellipse.
    expect(at(c.dx + 9, c.dy), (r: 250, g: 251, b: 252, a: 255));
    // The side wall under the top: light grey #E3E6E9 -> #D5DADF.
    final wall = at(c.dx, c.dy + g.top.height / 2 + 1.5);
    expect(wall.a, 255);
    expect(wall.r, inInclusiveRange(0xD5, 0xE3));
    expect(wall.b, inInclusiveRange(0xDF, 0xE9));
    visual.image.dispose();
  });

  test('the ellipses follow the tilt; a flat map gets the round dot', () {
    expect(MoveraRiderPuckMarker.tiltBucket(0), 0);
    expect(MoveraRiderPuckMarker.tiltBucket(3), 0);
    expect(MoveraRiderPuckMarker.tiltBucket(67.5), 70);
    final flat = MoveraRiderPuckMarker.geometry(0);
    expect(flat.top.width, flat.top.height);
    expect(flat.wall, 0);
    double ratioAt(double tilt) {
      final g = MoveraRiderPuckMarker.geometry(tilt);
      return g.top.height / g.top.width;
    }

    expect(ratioAt(20), lessThan(1));
    expect(ratioAt(40), lessThan(ratioAt(20)));
    expect(ratioAt(67.5), MoveraRiderPuckMarker.fullLeanRatio);
  });

  test('owner: "Blue must be same in all zoom steps": the maps keep the '
      'flat pin, its blue 9 pt, at every zoom and tilt', () async {
    expect(MoveraRiderPuckMarker.tiltsWithCamera, isFalse);
    const ratio = 3.0;
    final visual = await MoveraRiderPuckMarker.createVisual(pixelRatio: ratio);
    final at = await reader(visual.image, ratio);
    final c = MoveraRiderPuckMarker.geometry(0).centre;
    // Blue out to 4.2 pt each way, white by 5.4 pt: a 9 pt round dot.
    for (final d in [
      const Offset(4.2, 0),
      const Offset(-4.2, 0),
      const Offset(0, 4.2),
      const Offset(0, -4.2),
    ]) {
      expect(at(c.dx + d.dx, c.dy + d.dy).b, 250, reason: '$d');
    }
    for (final d in [const Offset(5.4, 0), const Offset(0, 5.4)]) {
      expect(at(c.dx + d.dx, c.dy + d.dy).r, 255, reason: '$d');
    }
    visual.image.dispose();
  });

  test('the anchor is the centre of the pin top', () {
    expect(MoveraRiderPuckMarker.anchorFor(0), const Offset(0.5, 0.5));
    final tilted = MoveraRiderPuckMarker.anchorFor(60);
    final g = MoveraRiderPuckMarker.geometry(60);
    expect(tilted.dx, 0.5);
    expect(tilted.dy * g.size.height, closeTo(g.centre.dy, 1e-9));
    expect(tilted.dy, lessThan(0.5), reason: 'the wall hangs below');
  });

  test('same size on screen at any zoom and at any pixel ratio', () async {
    for (final ratio in [1.0, 2.0, 2.625, 3.0]) {
      final visual = await MoveraRiderPuckMarker.createVisual(
        pixelRatio: ratio,
      );
      final icon = visual.icon as BytesMapBitmap;
      // The logical size never changes; only the pixel density does.
      expect(icon.width, closeTo(visual.size.width, 1e-9));
      expect(
        icon.width,
        closeTo(MoveraRiderPuckMarker.geometry(0).size.width, 1 / ratio),
      );
      expect(icon.imagePixelRatio, ratio);
      expect(visual.image.width, (icon.width! * ratio).round());
      visual.image.dispose();
    }
  });

  group('halo', () {
    test('grey #7797A8 at about 35 %', () {
      const color = RiderAccuracyHalo.color;
      expect(color.withValues(alpha: 1), const Color(0xFF7797A8));
      expect(color.a, closeTo(0.35, 0.01));
      // Over a light map (#F5F6F7) it reads about #CBD6DC.
      const map = Color(0xFFF5F6F7);
      final seen = Color.alphaBlend(color, map);
      expect((seen.r * 255).round(), closeTo(0xCB, 8));
      expect((seen.g * 255).round(), closeTo(0xD6, 8));
      expect((seen.b * 255).round(), closeTo(0xDC, 8));
    });

    test('a 120 pt screen-space disc at every pixel ratio: flat colour, no '
        'border, round', () async {
      for (final ratio in [1.0, 2.0, 2.625, 3.0]) {
        final visual = await RiderAccuracyHalo.createVisual(pixelRatio: ratio);
        final icon = visual.icon as BytesMapBitmap;
        expect(icon.width, closeTo(120, 1 / ratio));
        expect(icon.height, closeTo(120, 1 / ratio));
        expect(icon.imagePixelRatio, ratio);
        final data = (await visual.image.toByteData(
          format: ui.ImageByteFormat.rawStraightRgba,
        ))!;
        ({int r, int g, int b, int a}) at(double x, double y) {
          final i =
              ((y * ratio).floor() * visual.image.width + (x * ratio).floor()) *
              4;
          return (
            r: data.getUint8(i),
            g: data.getUint8(i + 1),
            b: data.getUint8(i + 2),
            a: data.getUint8(i + 3),
          );
        }

        // The same colour from the centre to just inside the edge: no
        // border, no gradient.
        for (final p in [
          const Offset(60, 60),
          const Offset(60, 3),
          const Offset(117, 60),
          const Offset(20, 60),
        ]) {
          final px = at(p.dx, p.dy);
          expect(px.a, closeTo(89, 2), reason: '$p @$ratio');
          expect(px.r, closeTo(0x77, 3), reason: '$p @$ratio');
          expect(px.g, closeTo(0x97, 3), reason: '$p @$ratio');
          expect(px.b, closeTo(0xA8, 3), reason: '$p @$ratio');
        }
        // Round: the square's corners are empty.
        expect(at(4, 4).a, 0);
        expect(at(116, 116).a, 0);
        visual.image.dispose();
      }
    });

    test('the halo bitmap is cached per pixel ratio', () {
      expect(
        identical(
          RiderAccuracyHalo.createIcon(pixelRatio: 3),
          RiderAccuracyHalo.createIcon(pixelRatio: 3),
        ),
        isTrue,
      );
    });
  });
}
