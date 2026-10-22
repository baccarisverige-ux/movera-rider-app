import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/auth/presentation/widgets/auth_scene.dart';
import 'package:movera_rider/features/auth/presentation/widgets/auth_style.dart';
import 'package:movera_rider/features/auth/presentation/widgets/movera_wordmark.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// The first screen's hero: the wordmark and the tagline. The wordmark is
/// complete from the first frame; only the small dot inside its pin waits
/// for the balloon that flies in from the scene and becomes it
/// ([BalloonFlight]).
class BalloonBrandIntro extends StatelessWidget {
  const BalloonBrandIntro({
    super.key,
    required this.progress,
    this.wordmarkKey,
  });

  /// The intro story; the flight itself is drawn by [BalloonFlight].
  final Animation<double> progress;

  /// Put on the wordmark so [BalloonFlight] can aim at its pin.
  final Key? wordmarkKey;

  /// Font size of the hero wordmark.
  static const wordmarkSize = 46.0;

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.of(context).disableAnimations;
    return Semantics(
      // rider-31: the slogan in the app language, as Rider name shows it.
      label: 'Movera. ${context.l10n.brandTaglineSentence}',
      child: ExcludeSemantics(
        child: SizedBox(
          height: 142,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 350),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 34),
                  AnimatedBuilder(
                    animation: progress,
                    builder: (context, _) {
                      final time = reducedMotion ? 1.0 : progress.value;
                      // Owner round 4: "Movera" is whole from the start; the
                      // dot in the "o" appears when the balloon lands and
                      // pops once (AnimatedScale in the wordmark).
                      return MoveraWordmark(
                        key: wordmarkKey,
                        size: wordmarkSize,
                        showDot: BalloonFlight.landed(time),
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      context.l10n.brandTaglineSentence,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      style: GoogleFonts.urbanist(
                        // 0.41 of the wordmark, as in the approved mock-up.
                        fontSize: 19,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                        color: AuthColors.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One continuous flight: the green balloon leaves the person's hand in the
/// scene, rises in a single arc to the hero wordmark, shrinks over the last
/// part of the way and settles inside the pin's hole as its small green dot.
///
/// Painted on a layer over the whole page, so there is no hand-over between
/// two painters half-way. When it lands the layer stops and the wordmark's
/// own dot takes over at the same spot and size, with a short pop.
class BalloonFlight extends StatelessWidget {
  const BalloonFlight({
    super.key,
    required this.progress,
    required this.sceneKey,
    required this.wordmarkKey,
    this.wordmarkSize = BalloonBrandIntro.wordmarkSize,
  });

  final Animation<double> progress;
  final GlobalKey sceneKey;
  final GlobalKey wordmarkKey;
  final double wordmarkSize;

  /// Story time when the balloon leaves the hand.
  static const releaseAt = 0.44;

  /// Story time when it has settled in the "o".
  static const landAt = 0.86;

  /// Share of the flight after which the balloon starts shrinking.
  static const shrinkFrom = 0.55;

  static bool released(double time) => time >= releaseAt;
  static bool landed(double time) => time >= landAt;

  static double _phase(double value, double start, double end) =>
      ((value - start) / (end - start)).clamp(0.0, 1.0).toDouble();

  /// How far along the flight the balloon is at [time], 0..1, eased.
  static double travel(double time) =>
      Curves.easeInOutCubic.transform(_phase(time, releaseAt, landAt));

  /// How far the balloon has shrunk to the dot, 0..1, over the last part
  /// of the flight ([shrinkFrom]..1 of [travel]).
  static double shrink(double time) =>
      Curves.easeInOutCubic.transform(_phase(travel(time), shrinkFrom, 1));

  /// The balloon's centre at [travel] on a soft arc from [from] to [to]: it
  /// rises first, then drifts across to the wordmark.
  static Offset along(Offset from, Offset to, double travel) {
    final control = Offset(
      from.dx + (to.dx - from.dx) * 0.15,
      from.dy + (to.dy - from.dy) * 0.75,
    );
    final u = 1 - travel;
    return from * (u * u) + control * (2 * u * travel) + to * (travel * travel);
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.of(context).disableAnimations;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: progress,
        builder: (context, _) {
          final time = reducedMotion ? 1.0 : progress.value;
          if (!released(time) || landed(time)) return const SizedBox.shrink();
          final overlay = context.findRenderObject() as RenderBox?;
          final scene =
              sceneKey.currentContext?.findRenderObject() as RenderBox?;
          final wordmark =
              wordmarkKey.currentContext?.findRenderObject() as RenderBox?;
          if (overlay == null ||
              scene == null ||
              wordmark == null ||
              !overlay.hasSize ||
              !scene.hasSize ||
              !wordmark.hasSize) {
            return const SizedBox.shrink();
          }
          final from = scene.localToGlobal(
            AuthScene.balloonCentre(scene.size),
            ancestor: overlay,
          );
          final layout = MoveraWordmark.layout(wordmarkSize);
          final to = wordmark.localToGlobal(
            layout.dotRect.center,
            ancestor: overlay,
          );
          // Same size as the balloon the scene drew, then the dot's size.
          final startRadius =
              AuthScene.balloonRadius *
              scene.size.width /
              AuthScene.designSize.width;
          final endRadius = layout.dotRect.width / 2;
          return CustomPaint(
            size: Size.infinite,
            painter: _FlightPainter(
              from: from,
              to: to,
              startRadius: startRadius,
              endRadius: endRadius,
              travel: travel(time),
              shrink: shrink(time),
            ),
          );
        },
      ),
    );
  }
}

class _FlightPainter extends CustomPainter {
  const _FlightPainter({
    required this.from,
    required this.to,
    required this.startRadius,
    required this.endRadius,
    required this.travel,
    required this.shrink,
  });

  final Offset from;
  final Offset to;
  final double startRadius;
  final double endRadius;
  final double travel;
  final double shrink;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = BalloonFlight.along(from, to, travel);
    final radius = startRadius + (endRadius - startRadius) * shrink;
    paintBalloon(
      canvas,
      centre,
      radius,
      // The string lets go early, the tail and the shine go as it shrinks.
      string: 1 - ((travel - 0.0) / 0.3).clamp(0.0, 1.0),
      body: 1 - shrink,
    );
  }

  /// A green balloon of [radius] at [centre]: a round body, a small tail
  /// below it and a shine, both fading with [body] (1 full, 0 a plain dot),
  /// and a short string fading with [string].
  static void paintBalloon(
    Canvas canvas,
    Offset centre,
    double radius, {
    required double string,
    required double body,
  }) {
    final green = Paint()..color = MoveraPin.dotColor;
    if (string > 0) {
      canvas.drawLine(
        centre + Offset(0, radius),
        centre + Offset(radius * 0.25, radius * 2.6),
        Paint()
          ..color = AuthColors.ink.withValues(alpha: string)
          ..strokeWidth = 1.1
          ..strokeCap = StrokeCap.round,
      );
    }
    if (body > 0) {
      final tail = radius * 0.28 * body;
      canvas.drawPath(
        Path()
          ..moveTo(centre.dx - tail, centre.dy + radius * 0.92)
          ..lineTo(centre.dx, centre.dy + radius + tail)
          ..lineTo(centre.dx + tail, centre.dy + radius * 0.92)
          ..close(),
        green,
      );
    }
    canvas.drawCircle(centre, radius, green);
    if (body > 0) {
      canvas.drawCircle(
        centre + Offset(-radius * 0.32, -radius * 0.38),
        radius * 0.3,
        Paint()..color = Colors.white.withValues(alpha: 0.38 * body),
      );
    }
  }

  @override
  bool shouldRepaint(_FlightPainter oldDelegate) =>
      oldDelegate.from != from ||
      oldDelegate.to != to ||
      oldDelegate.startRadius != startRadius ||
      oldDelegate.endRadius != endRadius ||
      oldDelegate.travel != travel ||
      oldDelegate.shrink != shrink;
}
