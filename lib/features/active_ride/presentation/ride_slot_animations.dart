import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:movera_rider/shared/widgets/slot_motion.dart';

/// Owner 2026-11-23, approved APPROVED-driver-coming.html: the same style
/// and 240x96 slot as the search radar, at the top of the panel. A faint
/// map, a blue route to the pickup, the driver's small car driving along it
/// and a soft green pulse on the pickup. Reduce motion: still.
class DriverComingAnimation extends StatelessWidget {
  const DriverComingAnimation({super.key});

  @override
  Widget build(BuildContext context) => SlotScene(
    fadeStops: const [0.48, 0.74],
    painter: (seconds, car) => _ComingPainter(seconds: seconds, car: car),
  );
}

const _acc = Color(0xFF1E3A8A);
const _green = Color(0xFF15803D);

/// The faint map both panels share (park, water, two side streets).
void _paintBaseMap(Canvas canvas, Path route) {
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 240, 96),
    Paint()..color = const Color(0xFFF6F7F4),
  );
  canvas.drawPath(
    Path()
      ..moveTo(0, 0)
      ..lineTo(70, 0)
      ..lineTo(70, 24)
      ..relativeCubicTo(-24, 6, -46, -4, -70, -10)
      ..close(),
    Paint()..color = const Color(0xFFE3EFE4),
  );
  canvas.drawPath(
    Path()
      ..moveTo(190, 76)
      ..relativeCubicTo(20, -6, 40, 0, 50, 6)
      ..lineTo(240, 96)
      ..lineTo(180, 96)
      ..close(),
    Paint()..color = const Color(0xFFDDE9F5),
  );
  canvas
    ..drawLine(
      const Offset(0, 30),
      const Offset(240, 30),
      _stroke(const Color(0xFFE4E6EA), 3),
    )
    ..drawLine(
      const Offset(150, 0),
      const Offset(150, 96),
      _stroke(const Color(0xFFE4E6EA), 3),
    )
    ..drawPath(route, _stroke(const Color(0xFFD8DBE0), 7))
    ..drawPath(route, _stroke(Colors.white, 4));
}

Paint _stroke(Color c, double w) => Paint()
  ..style = PaintingStyle.stroke
  ..strokeCap = StrokeCap.round
  ..color = c
  ..strokeWidth = w;

/// Draws [path] dashed ([on], [off]) starting [phase] along it.
void _dashed(
  Canvas canvas,
  Path path,
  Paint paint,
  double on,
  double off, {
  double phase = 0,
}) {
  for (final m in path.computeMetrics()) {
    var d = -(phase % (on + off));
    while (d < m.length) {
      final a = math.max(d, 0.0), b = math.min(d + on, m.length);
      if (b > a) canvas.drawPath(m.extractPath(a, b), paint);
      d += on + off;
    }
  }
}

void _carAlong(Canvas canvas, ui.Image? car, Path route, double t) {
  if (car == null) return;
  final m = route.computeMetrics().first;
  final tan = m.getTangentForOffset(m.length * t);
  if (tan == null) return;
  drawSlotCar(canvas, car, tan.position, -tan.angle, width: 14);
}

class _ComingPainter extends CustomPainter {
  _ComingPainter({required this.seconds, required this.car});

  final double seconds;
  final ui.Image? car;

  static final Path _route = Path()
    ..moveTo(30, 78)
    ..cubicTo(70, 74, 90, 50, 120, 52)
    ..cubicTo(150, 54, 160, 44, 186, 40);
  static const _pin = Offset(186, 40);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 240, size.height / 96);
    _paintBaseMap(canvas, _route);
    // The route's dashes run toward the pickup (18 px every 1.2 s).
    _dashed(
      canvas,
      _route,
      _stroke(_acc, 2.4),
      4,
      5,
      phase: -(seconds % 1.2) / 1.2 * 18,
    );
    // Soft green pulse on the pickup, every 2.4 s.
    final p = Curves.easeOut.transform((seconds % 2.4) / 2.4);
    canvas.drawCircle(
      _pin,
      6 * (0.4 + 2.8 * p),
      Paint()..color = _green.withValues(alpha: 0.4 * 0.6 * (1 - p)),
    );
    canvas.drawCircle(_pin, 6, Paint()..color = _green.withValues(alpha: .4));
    canvas.drawCircle(_pin, 5.5, Paint()..color = _green);
    canvas.drawCircle(_pin, 5.5, _stroke(Colors.white, 2.5));
    // The car drives to 92 % of the route in 85 % of 6 s, then waits.
    final f = (seconds % 6) / 6;
    _carAlong(canvas, car, _route, f < 0.85 ? f / 0.85 * 0.92 : 0.92);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ComingPainter old) =>
      old.seconds != seconds || old.car != car;
}

/// Owner 2026-11-23, approved on-trip-animation.html (LAUNCH-RULE.md: all
/// three panel animations approved): the same slot at the top of the trip
/// panel. The route from pickup to destination: the driven part turns solid
/// blue, the rest stays dotted; the car drives toward a small flag.
/// Reduce motion: still.
class OnTripAnimation extends StatelessWidget {
  const OnTripAnimation({super.key});

  @override
  Widget build(BuildContext context) => SlotScene(
    fadeStops: const [0.48, 0.74],
    painter: (seconds, car) => _TripPainter(seconds: seconds, car: car),
  );
}

class _TripPainter extends CustomPainter {
  _TripPainter({required this.seconds, required this.car});

  final double seconds;
  final ui.Image? car;

  static final Path _route = Path()
    ..moveTo(34, 74)
    ..cubicTo(70, 70, 92, 50, 124, 52)
    ..cubicTo(156, 54, 168, 42, 200, 40);
  static const _flag = Offset(200, 40);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 240, size.height / 96);
    _paintBaseMap(canvas, _route);
    _dashed(canvas, _route, _stroke(const Color(0xFF93A3C8), 2), 3, 5);
    // One trip every 8 s: the driven part and the car move together.
    final t = (seconds % 8) / 8;
    final m = _route.computeMetrics().first;
    canvas.drawPath(m.extractPath(0, m.length * t), _stroke(_acc, 3));
    canvas.drawCircle(const Offset(34, 74), 4, Paint()..color = _green);
    canvas.drawCircle(const Offset(34, 74), 4, _stroke(Colors.white, 2));
    // The flag waves a little (0 to -6 degrees and back, 1.6 s each way).
    final w = (seconds % 3.2) / 1.6;
    final wave = Curves.easeInOut.transform(w <= 1 ? w : 2 - w);
    canvas.save();
    canvas.translate(_flag.dx, 34);
    canvas.rotate(-6 * math.pi / 180 * wave);
    canvas.translate(-_flag.dx, -34);
    canvas.drawLine(
      _flag,
      const Offset(200, 24),
      _stroke(const Color(0xFF111111), 1.6)..strokeCap = StrokeCap.butt,
    );
    canvas.drawPath(
      Path()
        ..moveTo(200, 24)
        ..relativeLineTo(11, 0)
        ..relativeLineTo(-3, 4)
        ..relativeLineTo(3, 4)
        ..relativeLineTo(-11, 0)
        ..close(),
      Paint()..color = const Color(0xFF111111),
    );
    canvas.restore();
    _carAlong(canvas, car, _route, t);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TripPainter old) =>
      old.seconds != seconds || old.car != car;
}
