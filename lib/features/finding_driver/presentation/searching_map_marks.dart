import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/core/constants/appcolors.dart';
import 'package:movera_rider/shared/widgets/movera_map_markers.dart'
    show markerPixelRatio;

/// Owner-approved colours of the searching screen (2026-11-23).
abstract final class SearchingMarkColors {
  /// The rider's dot when the location is known.
  static const Color known = AppColor.blue;

  /// The rider's dot when there is no location (no permission / no fix).
  static const Color unknown = Color(0xFF8D9299);

  /// The "!" badge and the locked pin.
  static const Color badge = AppColor.navy;

  /// The black pill buttons of the share sheet and the pickup edit card.
  static const Color pill = Color(0xFF111614);
}

/// Owner 2026-11-23: the rider's own marker on the searching map — a white
/// walking man in a 32 px dot with a white ring. Blue with a soft halo when
/// the location is known; grey without halo, a small navy "!" badge and a
/// gentle pulse (a thin ring, [pulse] 0..1) when it is not.
abstract final class SearchingRiderMarker {
  static const double dot = 32;
  static const double ring = 3;
  static const double halo = 30;

  /// The bitmap's side in logical points (the halo fits).
  static const double side = halo * 2 + 4;

  /// Anchored at the dot's centre.
  static const Offset anchor = Offset(0.5, 0.5);

  static final Map<(bool, int), BitmapDescriptor> _cache = {};

  /// The marker for [known] (blue) or not (grey, badge); [pulse] is the
  /// pulse step of the grey marker (0 = no ring).
  static Future<BitmapDescriptor> createIcon({
    required bool known,
    double pulse = 0,
  }) {
    final step = known ? 0 : (pulse.clamp(0.0, 1.0) * 4).round();
    final key = (known, step);
    final done = _cache[key];
    if (done != null) return Future.value(done);
    return _bitmap(Size.square(side), (canvas) {
      paint(canvas, known: known, pulse: step / 4);
    }).then((icon) => _cache[key] = icon);
  }

  static void paint(Canvas canvas, {required bool known, double pulse = 0}) {
    const c = Offset(side / 2, side / 2);
    if (known) {
      canvas.drawCircle(
        c,
        halo,
        Paint()..color = SearchingMarkColors.known.withValues(alpha: 0.16),
      );
    } else if (pulse > 0) {
      canvas.drawCircle(
        c,
        dot / 2 + ring + (halo - dot / 2 - ring) * pulse,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = SearchingMarkColors.unknown.withValues(
            alpha: 0.55 * (1 - pulse) + 0.1,
          ),
      );
    }
    canvas
      ..drawCircle(
        c.translate(0, 1),
        dot / 2 + ring,
        Paint()
          ..color = const Color(0x331B2733)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      )
      ..drawCircle(c, dot / 2 + ring, Paint()..color = Colors.white)
      ..drawCircle(
        c,
        dot / 2,
        Paint()
          ..color = known
              ? SearchingMarkColors.known
              : SearchingMarkColors.unknown,
      );
    _glyph(canvas, Icons.directions_walk_rounded, c, 20, Colors.white);
    if (!known) {
      const b = Offset(side / 2 + 13, side / 2 - 13);
      canvas
        ..drawCircle(b, 8, Paint()..color = Colors.white)
        ..drawCircle(b, 6.5, Paint()..color = SearchingMarkColors.badge);
      final text = TextPainter(
        text: TextSpan(
          text: '!',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(canvas, b - Offset(text.width / 2, text.height / 2));
    }
  }
}

/// Owner 2026-11-23: the small white "Justera" pill with a lock beside the
/// locked pickup pin. The bitmap starts [gap] points right of the pin, so
/// it is anchored at its left edge, half height.
abstract final class AdjustPillMarker {
  static const double gap = 22;
  static const double height = 30;

  static final Map<String, BitmapDescriptor> _cache = {};

  static const Offset anchor = Offset(0, 0.5);

  static Future<BitmapDescriptor> createIcon(String label) {
    final done = _cache[label];
    if (done != null) return Future.value(done);
    return _create(label).then((icon) => _cache[label] = icon);
  }

  static TextPainter _label(String label) => TextPainter(
    text: TextSpan(
      text: label,
      style: GoogleFonts.poppins(
        color: AppColor.navy,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  /// The bitmap's size for [label], in logical points.
  static Size sizeFor(String label) =>
      Size(gap + 10 + 15 + 6 + _label(label).width + 12 + 4, height + 6);

  /// Paints the pill for [label] (origin top left of [sizeFor]).
  static void paint(Canvas canvas, String label) {
    final text = _label(label);
    final pillW = 10 + 15 + 6 + text.width + 12;
    final pill = RRect.fromRectAndRadius(
      Rect.fromLTWH(gap, 3, pillW, height),
      const Radius.circular(height / 2),
    );
    canvas
      ..drawRRect(
        pill.shift(const Offset(0, 1)),
        Paint()
          ..color = const Color(0x2E1B2733)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      )
      ..drawRRect(pill, Paint()..color = Colors.white)
      ..drawRRect(
        pill,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0xFFE7EBEE),
      );
    _glyph(
      canvas,
      Icons.lock_outline_rounded,
      const Offset(gap + 10 + 7.5, 3 + height / 2),
      15,
      AppColor.navy,
    );
    text.paint(
      canvas,
      Offset(gap + 10 + 15 + 6, 3 + (height - text.height) / 2),
    );
  }

  static Future<BitmapDescriptor> _create(String label) =>
      _bitmap(sizeFor(label), (canvas) => paint(canvas, label));
}

void _glyph(Canvas canvas, IconData icon, Offset centre, double size, Color c) {
  final painter = TextPainter(
    text: TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        fontSize: size,
        color: c,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  painter.paint(canvas, centre - Offset(painter.width / 2, painter.height / 2));
}

Future<BitmapDescriptor> _bitmap(Size size, void Function(Canvas) draw) async {
  const ratio = markerPixelRatio;
  final width = (size.width * ratio).ceil();
  final height = (size.height * ratio).ceil();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(ratio, ratio);
  draw(canvas);
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (data == null) {
    return BitmapDescriptor.bytes(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      ),
    );
  }
  return BitmapDescriptor.bytes(
    data.buffer.asUint8List(),
    width: width / ratio,
    height: height / ratio,
    imagePixelRatio: ratio,
  );
}
