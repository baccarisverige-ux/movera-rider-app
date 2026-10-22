import 'package:flutter/material.dart';
import 'package:movera_rider/features/auth/presentation/widgets/auth_style.dart';

/// The calm sign-in illustration: a soft green glow, a generic skyline, an arched
/// bridge over water, a road with the green route, trees and a street lamp.
///
/// Drawn on a 390x230 design canvas scaled to the available width and
/// anchored to the bottom, so it needs no image assets and simply fills
/// whatever height is left above the sign-in card: when space is short the
/// sky is trimmed and the road, bridge and water stay. When [showCar] is set,
/// a car eases in along the road once (no endless animation, so tests can
/// settle).
class AuthScene extends StatefulWidget {
  const AuthScene({super.key, this.showCar = true, this.storyProgress});

  final bool showCar;
  final Animation<double>? storyProgress;

  static const designSize = Size(390, 230);

  /// Where a point of the design canvas lands in a scene of [size]: the
  /// canvas is scaled to the width and anchored to the bottom, as painted.
  static Offset designToLocal(Size size, Offset design) {
    final s = size.width / designSize.width;
    return Offset(
      design.dx * s,
      size.height - designSize.height * s + design.dy * s,
    );
  }

  /// The centre of the balloon in the person's hand, in a scene of [size].
  static Offset balloonCentre(Size size) =>
      designToLocal(size, _ScenePainter._balloon);

  /// The balloon's radius on the design canvas (BalloonFlight starts at it).
  static const balloonRadius = _ScenePainter._balloonRadius;

  @override
  State<AuthScene> createState() => _AuthSceneState();
}

class _AuthSceneState extends State<AuthScene>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drive = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (widget.storyProgress != null) return;
    if (reduceMotion) {
      _drive.value = 1;
    } else if (_drive.status == AnimationStatus.dismissed) {
      _drive.forward();
    }
  }

  @override
  void dispose() {
    _drive.dispose();
    super.dispose();
  }

  double _storyCarProgress(double time) {
    double phase(double start, double end) =>
        ((time - start) / (end - start)).clamp(0.0, 1.0).toDouble();
    if (time < 0.43) {
      return 0.62 * Curves.easeInOutCubic.transform(phase(0.04, 0.43));
    }
    if (time < 0.64) {
      return 0.62; // Wait while the person boards.
    }
    return 0.62 + 0.38 * Curves.easeInOutCubic.transform(phase(0.64, 0.98));
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: widget.storyProgress ?? _drive,
        builder: (context, _) => CustomPaint(
          size: Size.infinite,
          painter: _ScenePainter(
            car: widget.showCar
                ? widget.storyProgress == null
                      ? Curves.easeOutCubic.transform(_drive.value)
                      : _storyCarProgress(widget.storyProgress!.value)
                : null,
            story: widget.storyProgress?.value,
          ),
        ),
      ),
    );
  }
}

class _ScenePainter extends CustomPainter {
  const _ScenePainter({this.car, this.story});

  /// 0..1 progress of the car along the road, or null for no car.
  final double? car;
  final double? story;

  static final _road = Path()
    ..moveTo(-10, 226)
    ..cubicTo(100, 196, 220, 206, 400, 180);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / AuthScene.designSize.width;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    // Bottom-anchored: any height shortfall trims the sky, never the road.
    canvas.translate(0, size.height - AuthScene.designSize.height * s);
    canvas.scale(s);
    canvas.clipRect(Offset.zero & AuthScene.designSize);
    _paintSky(canvas);
    _paintCity(canvas);
    _paintWater(canvas);
    _paintRoad(canvas);
    _paintTrees(canvas);
    if (story != null) _paintPerson(canvas, story!);
    final progress = car;
    if (progress != null) _paintCar(canvas, progress);
    canvas.restore();
  }

  void _paintSky(Canvas canvas) {
    const sun = Offset(300, 58);
    canvas.drawCircle(
      sun,
      60,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFFD9EAE0), Color(0xFFE9F2EC), Color(0x00F7F8F6)],
          stops: [0, 0.6, 1],
        ).createShader(Rect.fromCircle(center: sun, radius: 60)),
    );
    canvas.drawCircle(sun, 24, Paint()..color = const Color(0x80E2EEE6));
    final bird = Paint()
      ..color = const Color(0xFF9CAAA1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (story == null) {
      canvas.drawPath(
        Path()
          ..moveTo(250, 34)
          ..lineTo(255, 38)
          ..lineTo(260, 34)
          ..moveTo(268, 26)
          ..lineTo(272, 29)
          ..lineTo(276, 26),
        bird,
      );
    }
  }

  void _paintCity(Canvas canvas) {
    canvas.drawPath(
      Path()
        ..moveTo(0, 128)
        ..cubicTo(60, 112, 110, 120, 160, 116)
        ..cubicTo(210, 112, 280, 108, 390, 118)
        ..lineTo(390, 150)
        ..lineTo(0, 150)
        ..close(),
      Paint()..color = const Color(0xFFECF1ED),
    );
    final building = Paint()..color = const Color(0xFFDCE6DF);
    const blocks = [
      Rect.fromLTWH(18, 98, 22, 46),
      Rect.fromLTWH(44, 86, 18, 58),
      Rect.fromLTWH(66, 106, 28, 38),
      Rect.fromLTWH(148, 100, 22, 44),
      Rect.fromLTWH(202, 104, 30, 40),
      Rect.fromLTWH(240, 94, 20, 50),
      Rect.fromLTWH(264, 108, 34, 36),
    ];
    for (final r in blocks) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(2)),
        building,
      );
    }
    // A domed hall and a spire, generic rather than any real landmark.
    canvas.drawPath(
      Path()
        ..moveTo(112, 144)
        ..lineTo(112, 96)
        ..arcToPoint(const Offset(140, 96), radius: const Radius.circular(14))
        ..lineTo(140, 144)
        ..close(),
      building,
    );
    canvas.drawPath(
      Path()
        ..moveTo(178, 144)
        ..lineTo(178, 80)
        ..lineTo(187, 52)
        ..lineTo(196, 80)
        ..lineTo(196, 144)
        ..close(),
      building,
    );
  }

  void _paintWater(Canvas canvas) {
    const water = Rect.fromLTWH(0, 142, 390, 40);
    canvas.drawRect(
      water,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFE3EBE7), Color(0xFFF0F4F1)],
        ).createShader(water),
    );
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(300, 158), width: 60, height: 6),
      Paint()..color = const Color(0xB3D8E8DE),
    );
    final glint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (final (a, b) in const [
      (Offset(20, 160), Offset(60, 160)),
      (Offset(120, 170), Offset(176, 170)),
      (Offset(230, 164), Offset(274, 164)),
      (Offset(320, 174), Offset(360, 174)),
    ]) {
      canvas.drawLine(a, b, glint);
    }
    final bridge = Paint()
      ..color = const Color(0xFFC7D6CC)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(0, 146), const Offset(250, 146), bridge);
    final arches = Path()..moveTo(10, 146);
    for (var x = 10.0; x < 210; x += 50) {
      arches.quadraticBezierTo(x + 25, 124, x + 50, 146);
    }
    arches.quadraticBezierTo(230, 128, 250, 146);
    canvas.drawPath(arches, bridge);
  }

  void _paintRoad(Canvas canvas) {
    const land = Rect.fromLTWH(0, 164, 390, 66);
    canvas.drawPath(
      Path()
        ..moveTo(0, 182)
        ..cubicTo(110, 172, 260, 176, 390, 164)
        ..lineTo(390, 230)
        ..lineTo(0, 230)
        ..close(),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF2F5F2), Color(0xFFE9EEEA)],
        ).createShader(land),
    );
    Paint stroke(Color c, double w) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(_road, stroke(const Color(0xFFDCE4DE), 26));
    canvas.drawPath(_road, stroke(const Color(0xFFF7F8F6), 18));
    canvas.drawPath(
      _road,
      stroke(AuthColors.deepGreen, 3)
        ..shader = const LinearGradient(
          colors: [AuthColors.deepGreen, Color(0xFF1A8759)],
        ).createShader(const Rect.fromLTWH(0, 170, 390, 60)),
    );
  }

  void _paintTrees(Canvas canvas) {
    final post = Paint()
      ..color = const Color(0xFF2F3A34)
      ..strokeWidth = 2.2;
    canvas.drawLine(const Offset(338, 176), const Offset(338, 120), post);
    canvas.drawPath(
      Path()
        ..moveTo(332, 120)
        ..lineTo(344, 120)
        ..lineTo(342, 112)
        ..lineTo(334, 112)
        ..close(),
      Paint()..color = const Color(0xFF2F3A34),
    );
    canvas.drawCircle(
      const Offset(338, 123),
      2.3,
      Paint()..color = const Color(0xFFE8F4EC),
    );

    canvas.drawLine(
      const Offset(370, 150),
      const Offset(370, 176),
      Paint()
        ..color = const Color(0xFF7C9183)
        ..strokeWidth = 3,
    );
    for (final (c, r, color) in const [
      (Offset(366, 132), 24.0, Color(0xFFB2CBB9)),
      (Offset(382, 116), 18.0, Color(0xFF9EBEA7)),
      (Offset(352, 118), 14.0, Color(0xFFC6D8CB)),
      (Offset(376, 140), 14.0, Color(0xFF8EAF98)),
      (Offset(20, 184), 14.0, Color(0xFFBDD4C3)),
      (Offset(38, 178), 11.0, Color(0xFFA7C5AE)),
    ]) {
      canvas.drawCircle(c, r, Paint()..color = color);
    }
  }

  void _paintPerson(Canvas canvas, double time) {
    double phase(double start, double end) =>
        ((time - start) / (end - start)).clamp(0.0, 1.0).toDouble();
    final boarding = Curves.easeInOut.transform(phase(0.47, 0.64));
    final personOpacity = 1 - phase(0.55, 0.64);
    if (personOpacity > 0) {
      canvas.save();
      // Move from the waiting spot toward the car door, then get inside.
      canvas.translate(-38 * boarding, 6 * boarding);
      final ink = Paint()
        ..color = AuthColors.deepGreen.withValues(alpha: personOpacity)
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(
        const Offset(284, 157),
        5,
        Paint()
          ..color = const Color(0xFFDBB994).withValues(alpha: personOpacity),
      );
      canvas.drawLine(const Offset(284, 163), const Offset(284, 181), ink);
      canvas.drawLine(const Offset(284, 167), const Offset(297, 169), ink);
      canvas.drawLine(const Offset(284, 169), const Offset(276, 177), ink);
      canvas.drawLine(const Offset(284, 181), const Offset(277, 192), ink);
      canvas.drawLine(const Offset(284, 181), const Offset(291, 191), ink);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(279, 164, 10, 16),
          const Radius.circular(3),
        ),
        Paint()
          ..color = const Color(0xFF6D9E7C).withValues(alpha: personOpacity),
      );
      canvas.restore();
    }

    // The balloon waits in the hand until BalloonFlight takes it over at
    // the very same spot (owner round 3: one continuous flight).
    if (time >= _balloonRelease) return;
    canvas.drawLine(
      const Offset(297, 169),
      _balloon + const Offset(0, 11),
      Paint()
        ..color = AuthColors.ink
        ..strokeWidth = 1,
    );
    canvas.drawCircle(
      _balloon,
      _balloonRadius,
      Paint()..color = AuthColors.green,
    );
    canvas.drawCircle(
      _balloon + const Offset(-3.5, -3.5),
      3,
      Paint()..color = Colors.white.withValues(alpha: 0.38),
    );
  }

  /// Story time when the balloon leaves the hand (BalloonFlight.releaseAt).
  static const _balloonRelease = 0.44;

  /// The balloon's centre on the design canvas while it is in the hand.
  static const _balloon = Offset(304, 141);
  static const _balloonRadius = 11.0;

  void _paintCar(Canvas canvas, double progress) {
    // Arrive at the person, pause for boarding, then continue to the right.
    final metric = _road.computeMetrics().first;
    final distance =
        metric.length *
        (story == null ? 0.08 + 0.30 * progress : 0.02 + 0.96 * progress);
    final tangent = metric.getTangentForOffset(distance);
    if (tangent == null) return;
    canvas.save();
    canvas.translate(
      tangent.position.dx - (story == null ? 0 : 50 * (1 - progress)),
      tangent.position.dy - 5,
    );
    canvas.rotate(-tangent.angle);
    canvas.translate(-31, -24);
    canvas.drawOval(
      const Rect.fromLTWH(5, 27, 60, 5),
      Paint()..color = const Color(0x1A000000),
    );
    final body = Path()
      ..moveTo(5, 20)
      ..cubicTo(5, 16.8, 7.3, 14.6, 10.4, 14.1)
      ..lineTo(19.4, 12.5)
      ..lineTo(26.6, 5.9)
      ..cubicTo(28.2, 4.5, 30.2, 3.7, 32.3, 3.7)
      ..lineTo(42.3, 3.7)
      ..cubicTo(44.8, 3.7, 47.2, 4.9, 48.7, 6.9)
      ..lineTo(53.1, 12.8)
      ..lineTo(58.5, 13.9)
      ..cubicTo(61.3, 14.5, 62.9, 16.7, 62.9, 19.3)
      ..lineTo(62.9, 23)
      ..cubicTo(62.9, 24.2, 61.9, 25.2, 60.7, 25.2)
      ..lineTo(7.2, 25.2)
      ..cubicTo(6, 25.2, 5, 24.2, 5, 23)
      ..close();
    canvas.drawPath(
      body,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF18513D), AuthColors.deepGreen],
        ).createShader(const Rect.fromLTWH(5, 3, 58, 23)),
    );
    canvas.drawPath(
      Path()
        ..moveTo(25, 12.6)
        ..lineTo(31.6, 6.8)
        ..cubicTo(32.7, 5.8, 34, 5.4, 35.4, 5.4)
        ..lineTo(43.1, 5.4)
        ..cubicTo(44.7, 5.4, 46.2, 6.2, 47.2, 7.5)
        ..lineTo(50.6, 12.6)
        ..close(),
      Paint()..color = const Color(0xFFE2EEE6),
    );
    canvas.drawLine(
      const Offset(38, 5.6),
      const Offset(38, 12.6),
      Paint()
        ..color = AuthColors.deepGreen
        ..strokeWidth = 1.6,
    );
    for (final x in const [19.0, 52.0]) {
      canvas.drawCircle(
        Offset(x, 25),
        5,
        Paint()..color = const Color(0xFF1B211E),
      );
      canvas.drawCircle(
        Offset(x, 25),
        2,
        Paint()..color = const Color(0xFFD8E2DA),
      );
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(58, 17, 4, 2.4),
        const Radius.circular(1),
      ),
      Paint()..color = const Color(0xFFE8F4EC),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ScenePainter oldDelegate) =>
      oldDelegate.car != car || oldDelegate.story != story;
}
