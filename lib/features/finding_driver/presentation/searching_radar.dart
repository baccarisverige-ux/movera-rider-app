import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:movera_rider/shared/widgets/slot_motion.dart';

/// Owner 2026-11-23 ("We also change this car card"), approved design
/// APPROVED-searching-radar.html: in the place of the white car picture, at
/// the same height, a faint map with roads, small cars driving on them and a
/// radar turning slowly in the middle. The edges fade into the white panel.
/// With "reduce motion" on, it stands still.
class SearchingRadar extends StatelessWidget {
  const SearchingRadar({super.key});

  @override
  Widget build(BuildContext context) => SlotScene(
    fadeStops: const [0.45, 0.72],
    painter: (seconds, car) => _RadarPainter(seconds: seconds, car: car),
  );
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({required this.seconds, required this.car});

  final double seconds;
  final ui.Image? car;

  static const _acc = Color(0xFF1E3A8A);

  static final Path _ra = Path()
    ..moveTo(-20, 70)
    ..cubicTo(50, 62, 90, 52, 130, 50)
    ..cubicTo(170, 48, 210, 34, 260, 28);
  static final Path _rb = Path()
    ..moveTo(70, -10)
    ..cubicTo(80, 30, 100, 60, 104, 110);
  static final Path _rc = Path()
    ..moveTo(260, 80)
    ..cubicTo(200, 76, 170, 60, 150, 40)
    ..cubicTo(130, 20, 120, 0, 110, -10);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 240, size.height / 96);
    _map(canvas);
    _cars(canvas);
    canvas.restore();
    _radar(canvas, size);
  }

  void _map(Canvas canvas) {
    // The map is see-through (0.55) so it stays faint.
    canvas.saveLayer(
      const Rect.fromLTWH(0, 0, 240, 96),
      Paint()..color = const Color(0x8C000000),
    );
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 240, 96),
      Paint()..color = const Color(0xFFF6F7F4),
    );
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(60, 0)
        ..lineTo(60, 26)
        ..relativeCubicTo(-20, 6, -40, -4, -60, -10)
        ..close(),
      Paint()..color = const Color(0xFFE3EFE4),
    );
    canvas.drawPath(
      Path()
        ..moveTo(190, 70)
        ..relativeCubicTo(20, -6, 40, 0, 50, 6)
        ..lineTo(240, 96)
        ..lineTo(180, 96)
        ..close(),
      Paint()..color = const Color(0xFFDDE9F5),
    );
    Paint road(Color c, double w) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..color = c
      ..strokeWidth = w;
    canvas
      ..drawLine(
        const Offset(0, 22),
        const Offset(240, 22),
        road(const Color(0xFFE4E6EA), 3),
      )
      ..drawLine(
        const Offset(200, 0),
        const Offset(200, 96),
        road(const Color(0xFFE4E6EA), 3),
      )
      ..drawPath(_ra, road(const Color(0xFFD8DBE0), 7))
      ..drawPath(_ra, road(Colors.white, 4))
      ..drawPath(_rb, road(const Color(0xFFD8DBE0), 6))
      ..drawPath(_rb, road(Colors.white, 3))
      ..drawPath(_rc, road(const Color(0xFFD8DBE0), 6))
      ..drawPath(_rc, road(Colors.white, 3));
    canvas.restore();
  }

  void _cars(Canvas canvas) {
    final img = car;
    if (img == null) return;
    // (road, period s, start offset s, backwards)
    _carOn(canvas, img, _ra, 9, 0, false);
    _carOn(canvas, img, _rb, 7, 3, false);
    _carOn(canvas, img, _rc, 10, 6, false);
    _carOn(canvas, img, _ra, 12, 8, true);
  }

  void _carOn(
    Canvas canvas,
    ui.Image img,
    Path road,
    double period,
    double offset,
    bool backwards,
  ) {
    final metric = road.computeMetrics().first;
    var t = ((seconds + offset) % period) / period;
    if (backwards) t = 1 - t;
    final tan = metric.getTangentForOffset(metric.length * t);
    if (tan == null) return;
    var angle = -tan.angle;
    if (backwards) angle += math.pi;
    drawSlotCar(canvas, img, tan.position, angle);
  }

  void _radar(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    // Sweep: one turn every 4 s.
    final turn = (seconds % 4) / 4 * 2 * math.pi;
    final sweepRect = Rect.fromCircle(center: c, radius: 100);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(turn - math.pi / 2);
    canvas.translate(-c.dx, -c.dy);
    canvas.drawCircle(
      c,
      100,
      Paint()
        ..shader = SweepGradient(
          colors: [
            _acc.withValues(alpha: 0.18),
            _acc.withValues(alpha: 0),
            Colors.transparent,
          ],
          stops: const [0, 55 / 360, 1],
        ).createShader(sweepRect),
    );
    canvas.restore();
    // Two rings, 2 s apart, growing out over 4 s.
    for (final delay in const [0.0, 2.0]) {
      final p = ((seconds - delay) % 4) / 4;
      final e = Curves.easeOut.transform(p);
      canvas.drawCircle(
        c,
        5 * (1 + 13 * e),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = _acc.withValues(alpha: 0.55 * 0.7 * (1 - e)),
      );
    }
    canvas.drawCircle(c, 9, Paint()..color = _acc.withValues(alpha: 0.12));
    canvas.drawCircle(c, 5, Paint()..color = _acc);
  }

  @override
  bool shouldRepaint(_RadarPainter old) =>
      old.seconds != seconds || old.car != car;
}
