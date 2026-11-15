import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/shared/widgets/movera_map_markers.dart'
    show markerPixelRatio;

/// The four saved-place pin pictures (owner 2026-11-01 "No thats enouth for
/// pin", Rules plan/rider-saved-pins/SPEC.md): Home, Work, Gym, and the
/// star for every other saved place.
enum SavedPinStyle { home, work, gym, star }

/// The style a saved place's kind gets: `home`, `office` / `work`, `gym`;
/// any other kind is the star.
SavedPinStyle savedPinStyleFor(String kind) {
  switch (kind.trim().toLowerCase()) {
    case 'home':
      return SavedPinStyle.home;
    case 'office':
    case 'work':
      return SavedPinStyle.work;
    case 'gym':
      return SavedPinStyle.gym;
    default:
      return SavedPinStyle.star;
  }
}

/// A saved-place pin bitmap: the drop with its picture, its point on the
/// ground at [anchor], the place's name under the point.
typedef SavedPinVisual = ({BitmapDescriptor icon, Offset anchor});

/// Draws the saved-place pins on the rider's Home map (owner 2026-10-31 /
/// 2026-11-01, Rules plan/rider-saved-pins/SPEC.md and
/// pins-home-work-gym.html, "one matching style"): one drop shape with the
/// dark outline [outline] and a soft shadow, about [width] points wide
/// (owner: "clear on the map but not so big"), the owner's pictures redrawn
/// in it (house with chimney · office with plant and clock · gym: four
/// pastel quarters with dumbbell and kettlebell · a yellow star for every
/// other place). The place's name sits under the point, small, with a white
/// halo.
///
/// The drawing follows the mockup's 60 x 80 viewBox; the bitmap is a
/// screen-fixed marker, the same size at every zoom.
abstract final class SavedPlacePinMarker {
  /// The drop's outline (mockup `O`).
  static const Color outline = Color(0xFF16485A);

  /// The drop's width on screen, in logical points.
  static const double width = 40;

  /// The mockup's viewBox.
  static const double _box = 60;
  static const double _scale = width / _box;

  /// The drop's tip in the viewBox: the point that sits on the address.
  static const Offset _tip = Offset(30, 76);

  /// The tallest the drop grows while it appears (bounce).
  static const double maxGrow = 1.15;

  static const double _side = 6;
  static const double _top = 4;
  static const double _labelGap = 1;
  static const double _labelSize = 12;
  static const int _labelMaxChars = 18;

  static const Color _labelInk = Color(0xFF1D252C);

  static Path _dropPath() => Path()
    ..moveTo(30, 76)
    ..cubicTo(30, 76, 6, 48, 6, 30)
    ..arcToPoint(
      const Offset(54, 30),
      radius: const Radius.circular(24),
      largeArc: true,
    )
    ..cubicTo(54, 48, 30, 76, 30, 76)
    ..close();

  static String _shortLabel(String label) {
    final clean = label.trim();
    if (clean.length <= _labelMaxChars) return clean;
    return '${clean.substring(0, _labelMaxChars - 1).trimRight()}…';
  }

  static TextPainter _labelPainter(String label, double opacity, bool halo) {
    final alpha = (opacity.clamp(0.0, 1.0) * 255).round();
    final style = TextStyle(
      fontSize: _labelSize,
      fontWeight: FontWeight.w700,
      height: 1.15,
      foreground: halo
          ? (Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3
              ..strokeJoin = StrokeJoin.round
              ..color = Colors.white.withAlpha(alpha))
          : (Paint()..color = _labelInk.withAlpha(alpha)),
    );
    return TextPainter(
      text: TextSpan(text: _shortLabel(label), style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
  }

  /// The bitmap's size for [label] and the drop tip's place in it. The size
  /// does not depend on the animation, so every frame of one place has the
  /// same anchor.
  static ({Size size, Offset tip}) layoutFor(String label) {
    final text = _labelPainter(label, 1, false);
    final dropBox = width * maxGrow + 2 * _side;
    final w = math.max(dropBox, text.width + 2 * _side).ceilToDouble();
    final tipY = (_top + _tip.dy * _scale * maxGrow).ceilToDouble();
    final h = (tipY + _labelGap + text.height + 4).ceilToDouble();
    text.dispose();
    return (size: Size(w, h), tip: Offset(w / 2, tipY));
  }

  /// Paints the pin for [label] in [style] on [canvas] (logical points).
  /// [grow] scales the drop about its tip (0: on the ground, 1: full size);
  /// [labelOpacity] fades the name in.
  static void paint(
    Canvas canvas,
    SavedPinStyle style,
    String label, {
    double grow = 1,
    double labelOpacity = 1,
  }) {
    final layout = layoutFor(label);
    final tip = layout.tip;
    final g = grow.clamp(0.0, maxGrow);
    if (g > 0) {
      canvas
        ..save()
        ..translate(tip.dx, tip.dy)
        ..scale(_scale * g, _scale * g)
        ..translate(-_tip.dx, -_tip.dy);
      final drop = _dropPath();
      // The mockup's drop-shadow(0 2px 2px rgba(0,0,0,.35)).
      canvas.drawPath(
        drop.shift(const Offset(0, 3)),
        Paint()
          ..color = const Color(0x59000000)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
      );
      _paintPicture(canvas, style, drop);
      canvas.restore();
    }
    if (labelOpacity > 0 && label.trim().isNotEmpty) {
      final halo = _labelPainter(label, labelOpacity, true);
      final ink = _labelPainter(label, labelOpacity, false);
      final at = Offset(tip.dx - ink.width / 2, tip.dy + _labelGap);
      halo.paint(canvas, at);
      ink.paint(canvas, at);
      halo.dispose();
      ink.dispose();
    }
  }

  static Paint _fill(Color color) => Paint()
    ..color = color
    ..isAntiAlias = true;

  static Paint _stroke(double w) => Paint()
    ..color = outline
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;

  static void _rect(
    Canvas canvas,
    Rect rect,
    Color fill,
    double stroke, {
    double radius = 0,
  }) {
    final r = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    canvas
      ..drawRRect(r, _fill(fill))
      ..drawRRect(r, _stroke(stroke));
  }

  static void _path(Canvas canvas, Path path, Color? fill, double stroke) {
    if (fill != null) canvas.drawPath(path, _fill(fill));
    canvas.drawPath(path, _stroke(stroke));
  }

  /// Two halves split at the middle (the mockup's 50 % gradient stop).
  static void _splitDrop(Canvas canvas, Path drop, Color left, Color right) {
    canvas
      ..save()
      ..clipPath(drop)
      ..drawRect(const Rect.fromLTWH(0, 0, 30, 80), _fill(left))
      ..drawRect(const Rect.fromLTWH(30, 0, 30, 80), _fill(right))
      ..restore()
      ..drawPath(drop, _stroke(3));
  }

  static void _paintPicture(Canvas canvas, SavedPinStyle style, Path drop) {
    switch (style) {
      case SavedPinStyle.home:
        _paintHome(canvas, drop);
      case SavedPinStyle.work:
        _paintWork(canvas, drop);
      case SavedPinStyle.gym:
        _paintGym(canvas, drop);
      case SavedPinStyle.star:
        _paintStar(canvas, drop);
    }
  }

  // Owner's Home picture: teal drop, cream house, red roof with chimney and
  // smoke, two blue windows, white arched door.
  static void _paintHome(Canvas canvas, Path drop) {
    _splitDrop(canvas, drop, const Color(0xFF5CC4D8), const Color(0xFF45B3C9));
    _path(
      canvas,
      Path()
        ..moveTo(44, 14)
        ..relativeCubicTo(-2, -2, 1, -4, -1, -6),
      null,
      1.4,
    );
    _rect(
      canvas,
      const Rect.fromLTWH(39, 15, 5, 7),
      const Color(0xFFE5603A),
      1.4,
    );
    _path(
      canvas,
      Path()
        ..moveTo(17, 31)
        ..lineTo(17, 44)
        ..lineTo(43, 44)
        ..lineTo(43, 31),
      const Color(0xFFFBE2AD),
      2,
    );
    _path(
      canvas,
      Path()
        ..moveTo(13, 32)
        ..lineTo(30, 18)
        ..lineTo(47, 32),
      const Color(0xFFE5603A),
      2,
    );
    _rect(
      canvas,
      const Rect.fromLTWH(20, 33, 6, 5),
      const Color(0xFF5CC4D8),
      1.3,
    );
    _rect(
      canvas,
      const Rect.fromLTWH(34, 33, 6, 5),
      const Color(0xFF5CC4D8),
      1.3,
    );
    _path(
      canvas,
      Path()
        ..moveTo(27, 44)
        ..lineTo(27, 40)
        ..arcToPoint(const Offset(33, 40), radius: const Radius.circular(3))
        ..lineTo(33, 44)
        ..close(),
      Colors.white,
      1.3,
    );
  }

  // Owner's Work picture: blue / lilac drop, cream office (six windows,
  // green arched door), potted plant, floor line, clock at the tip.
  static void _paintWork(Canvas canvas, Path drop) {
    _splitDrop(canvas, drop, const Color(0xFFB9DCF5), const Color(0xFFD3C4F2));
    _rect(
      canvas,
      const Rect.fromLTWH(17, 14, 20, 28),
      const Color(0xFFFBECC0),
      2,
    );
    _rect(
      canvas,
      const Rect.fromLTWH(31, 10, 3, 4),
      const Color(0xFFE5603A),
      1,
    );
    for (var c = 0; c < 3; c++) {
      for (var r = 0; r < 2; r++) {
        _rect(
          canvas,
          Rect.fromLTWH(19.5 + c * 5.5, 17 + r * 7.0, 4, 4.5),
          const Color(0xFFBFEEE6),
          1,
        );
      }
    }
    _path(
      canvas,
      Path()
        ..moveTo(24, 42)
        ..lineTo(24, 37)
        ..arcToPoint(const Offset(30, 37), radius: const Radius.circular(3))
        ..lineTo(30, 42)
        ..close(),
      const Color(0xFF8FD9B6),
      1.2,
    );
    _path(
      canvas,
      Path()
        ..moveTo(40, 41)
        ..lineTo(46, 41)
        ..lineTo(45, 37)
        ..lineTo(41, 37)
        ..close(),
      const Color(0xFFE8B97A),
      1.1,
    );
    _path(
      canvas,
      Path()
        ..moveTo(43, 37)
        ..relativeCubicTo(-4, -4, -6, -8, -3, -10)
        ..relativeCubicTo(1, 4, 3, 6, 3, 10)
        ..close()
        ..moveTo(43, 37)
        ..relativeCubicTo(3, -4, 6, -6, 7, -4)
        ..relativeCubicTo(-2, 2, -4, 3, -7, 4)
        ..close(),
      const Color(0xFF8FD9B6),
      1,
    );
    canvas.drawLine(const Offset(13, 43), const Offset(48, 43), _stroke(2));
    canvas
      ..drawCircle(const Offset(30, 57), 7, _fill(const Color(0xFFBFEEE6)))
      ..drawCircle(const Offset(30, 57), 7, _stroke(2));
    _path(
      canvas,
      Path()
        ..moveTo(30, 53)
        ..lineTo(30, 57.5)
        ..lineTo(33, 59),
      null,
      1.5,
    );
  }

  // Owner's Gym picture, "fix if need it": four pastel quarters, a big
  // dumbbell and a kettlebell (treadmill and yoga left out at 40 pt).
  static void _paintGym(Canvas canvas, Path drop) {
    canvas
      ..save()
      ..clipPath(drop)
      ..drawRect(
        const Rect.fromLTWH(0, 0, 30, 31),
        _fill(const Color(0xFFC8ECC6)),
      )
      ..drawRect(
        const Rect.fromLTWH(30, 0, 30, 31),
        _fill(const Color(0xFFFBEFB0)),
      )
      ..drawRect(
        const Rect.fromLTWH(0, 31, 30, 50),
        _fill(const Color(0xFFBFE3F3)),
      )
      ..drawRect(
        const Rect.fromLTWH(30, 31, 30, 50),
        _fill(const Color(0xFFF7C9CF)),
      )
      ..restore()
      ..drawPath(drop, _stroke(3));
    const lilac = Color(0xFFC9B8F0);
    _rect(
      canvas,
      const Rect.fromLTWH(17, 28.5, 26, 4),
      const Color(0xFFFBE2AD),
      1.6,
      radius: 1,
    );
    _rect(canvas, const Rect.fromLTWH(11, 21, 6, 19), lilac, 2, radius: 2);
    _rect(canvas, const Rect.fromLTWH(43, 21, 6, 19), lilac, 2, radius: 2);
    _rect(canvas, const Rect.fromLTWH(7, 25, 4, 11), lilac, 1.6, radius: 1.5);
    _rect(canvas, const Rect.fromLTWH(49, 25, 4, 11), lilac, 1.6, radius: 1.5);
    _path(
      canvas,
      Path()
        ..moveTo(26, 47)
        ..arcToPoint(const Offset(34, 47), radius: const Radius.circular(4)),
      null,
      2,
    );
    canvas
      ..drawCircle(const Offset(30, 53), 5.5, _fill(lilac))
      ..drawCircle(const Offset(30, 53), 5.5, _stroke(2));
  }

  // The default pin (owner: "default (star) for any other saved place, same
  // style"): the matching drop with a yellow star.
  static void _paintStar(Canvas canvas, Path drop) {
    _splitDrop(canvas, drop, const Color(0xFFB9DCF5), const Color(0xFFA6CFEF));
    final star = Path();
    const centre = Offset(30, 31);
    for (var i = 0; i < 10; i++) {
      final r = i.isEven ? 15.0 : 6.6;
      final a = -math.pi / 2 + i * math.pi / 5;
      final p = centre + Offset(math.cos(a) * r, math.sin(a) * r);
      if (i == 0) {
        star.moveTo(p.dx, p.dy);
      } else {
        star.lineTo(p.dx, p.dy);
      }
    }
    star.close();
    _path(canvas, star, const Color(0xFFFFCF3F), 2);
  }

  /// The pin bitmap for [label] in [style] at [pixelRatio], with its decoded
  /// image (tests read its pixels).
  static Future<({SavedPinVisual visual, ui.Image image})> createVisual(
    SavedPinStyle style,
    String label, {
    double grow = 1,
    double labelOpacity = 1,
    double pixelRatio = markerPixelRatio,
  }) async {
    final ratio = pixelRatio.isFinite && pixelRatio > 0 ? pixelRatio : 1.0;
    final layout = layoutFor(label);
    final w = (layout.size.width * ratio).ceil();
    final h = (layout.size.height * ratio).ceil();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(ratio, ratio);
    paint(canvas, style, label, grow: grow, labelOpacity: labelOpacity);
    final image = await recorder.endRecording().toImage(w, h);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final icon = data == null
        // Never Google's red default pin: an invisible one instead.
        ? BitmapDescriptor.bytes(
            base64Decode(
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
            ),
          )
        : BitmapDescriptor.bytes(
            data.buffer.asUint8List(),
            width: w / ratio,
            height: h / ratio,
            imagePixelRatio: ratio,
          );
    final anchor = Offset(
      layout.tip.dx / layout.size.width,
      layout.tip.dy / layout.size.height,
    );
    return (visual: (icon: icon, anchor: anchor), image: image);
  }

  /// The pin bitmap only (see [createVisual]).
  static Future<SavedPinVisual> create(
    SavedPinStyle style,
    String label, {
    double grow = 1,
    double labelOpacity = 1,
    double pixelRatio = markerPixelRatio,
  }) async {
    final result = await createVisual(
      style,
      label,
      grow: grow,
      labelOpacity: labelOpacity,
      pixelRatio: pixelRatio,
    );
    result.image.dispose();
    return result.visual;
  }
}
