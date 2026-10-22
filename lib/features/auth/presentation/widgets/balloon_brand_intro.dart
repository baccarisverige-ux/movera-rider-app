import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/auth/presentation/widgets/auth_scene.dart';
import 'package:movera_rider/features/auth/presentation/widgets/auth_style.dart';
import 'package:movera_rider/features/auth/presentation/widgets/movera_wordmark.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// The first screen's hero: the wordmark and the tagline. The wordmark is
/// complete from the first frame; during the intro story the balloon from
/// the scene flies in and settles onto its pin ([BalloonFlight]).
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
                  // Owner round 3: the wordmark always reads "Movera", pin
                  // included; the balloon lands onto that pin and ends up
                  // identical to it.
                  MoveraWordmark(key: wordmarkKey, size: wordmarkSize),
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

/// One continuous flight: the balloon leaves the person's hand in the scene,
/// rises in a single curve to the hero wordmark and settles onto its pin,
/// darkening into the same black on the way.
///
/// Painted on a layer over the whole page, so there is no hand-over between
/// two painters half-way (the old intro drew the first half in the scene and
/// the second in the hero, in different coordinates and speeds, which showed
/// as a stall and a jump in the middle).
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

  /// Story time when it has become the pin.
  static const landAt = 0.86;

  static bool released(double time) => time >= releaseAt;
  static bool landed(double time) => time >= landAt;

  static double _phase(double value, double start, double end) =>
      ((value - start) / (end - start)).clamp(0.0, 1.0).toDouble();

  /// How far along the flight the balloon is at [time], 0..1, eased.
  static double travel(double time) =>
      Curves.easeInOutCubic.transform(_phase(time, releaseAt, landAt));

  /// How much balloon has turned into pin at [time], 0..1.
  static double morph(double time) =>
      Curves.easeOut.transform(_phase(time, 0.68, landAt));

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
          final pinScale = layout.pinRect.height / MoveraPin.designSize.height;
          final to = wordmark.localToGlobal(
            layout.pinRect.topLeft + MoveraPin.headCentre * pinScale,
            ancestor: overlay,
          );
          return CustomPaint(
            size: Size.infinite,
            painter: _FlightPainter(
              from: from,
              to: to,
              scale: pinScale,
              travel: travel(time),
              morph: morph(time),
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
    required this.scale,
    required this.travel,
    required this.morph,
  });

  final Offset from;
  final Offset to;
  final double scale;
  final double travel;
  final double morph;

  @override
  void paint(Canvas canvas, Size size) {
    // A gentle arc: the balloon drifts a little sideways on the way up.
    final drift = Offset(18 * math.sin(math.pi * travel), 0);
    final centre = Offset.lerp(from, to, travel)! + drift;
    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    canvas.scale(scale);
    canvas.translate(-MoveraPin.headCentre.dx, -MoveraPin.headCentre.dy);
    // Colour follows the whole flight, form only the last part: no sudden
    // change of colour on landing.
    paintBalloon(canvas, morph, tone: travel);
    canvas.restore();
  }

  /// The balloon on [MoveraPin.designSize]: round and all green when it
  /// leaves the hand; over the flight ([tone] 0..1) its head darkens into
  /// the pin's ink while the tip stays green, so it arrives already in the
  /// pin's colours; [shape] 0..1 is the form, balloon to pin with its hole.
  static void paintBalloon(Canvas canvas, double shape, {double? tone}) {
    final t = tone ?? shape;
    final tip = 31 + 11 * shape;
    final head = Color.lerp(MoveraPin.bottomColor, MoveraPin.topColor, t)!;
    canvas.drawPath(
      MoveraPin.withHole(tip: tip, hole: MoveraPin.holeRadius * shape),
      MoveraPin.fill(top: head),
    );
    if (t < 1) {
      canvas.drawCircle(
        const Offset(11, 10),
        4.5,
        Paint()..color = Colors.white.withValues(alpha: 0.38 * (1 - t)),
      );
    }
    if (shape < 1) {
      canvas.drawPath(
        Path()
          ..moveTo(16, tip)
          ..quadraticBezierTo(19, 37, 16, 42),
        Paint()
          ..color = AuthColors.ink.withValues(alpha: 1 - shape)
          ..strokeWidth = 1.2
          ..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(_FlightPainter oldDelegate) =>
      oldDelegate.from != from ||
      oldDelegate.to != to ||
      oldDelegate.scale != scale ||
      oldDelegate.travel != travel ||
      oldDelegate.morph != morph;
}
