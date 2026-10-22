import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/auth/presentation/widgets/auth_style.dart';

/// The one Movera wordmark: "Mov" in ink, the map pin as the "o" (ink
/// running into green from head to tip), "era" in green. Every sign-in screen draws this same widget, only at another
/// [size], so the mark is identical everywhere (owner round 3).
///
/// Proportions follow the approved mock-up and are relative to the font
/// size, so they hold at any size:
///  * the top of the pin sits on the x-height, level with the top of the "v";
///  * the pin's tip ends [MoveraPin.tipBelowBaseline] under the baseline;
///  * [MoveraPin.gap] of air on each side of the pin.
class MoveraWordmark extends StatelessWidget {
  const MoveraWordmark({super.key, this.size = 27, this.pinOpacity = 1});

  final double size;

  /// 0 hides the pin (the brand intro draws a balloon there instead).
  final double pinOpacity;

  static TextStyle textStyle(double size) => GoogleFonts.urbanist(
    fontSize: size,
    height: 1,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.01 * size,
    color: AuthColors.ink,
  );

  /// Where each part lands for [size]; the brand intro aims the balloon at
  /// [MoveraWordmarkLayout.pinRect].
  static MoveraWordmarkLayout layout(double size) {
    final style = textStyle(size);
    TextPainter measure(String text) => TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final m = measure('M');
    final vera = measure('vera');
    final baseline = m.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    final pinHeight = MoveraPin.height * size;
    final pinWidth = pinHeight * MoveraPin.aspect;
    final gap = MoveraPin.gap * size;
    final pinLeft = m.width + gap;
    final pinTop = baseline - MoveraPin.xHeight * size;
    final layout = MoveraWordmarkLayout(
      size: Size(pinLeft + pinWidth + gap + vera.width, size),
      baseline: baseline,
      mLeft: 0,
      veraLeft: pinLeft + pinWidth + gap,
      pinRect: Rect.fromLTWH(pinLeft, pinTop, pinWidth, pinHeight),
    );
    m.dispose();
    vera.dispose();
    return layout;
  }

  @override
  Widget build(BuildContext context) {
    final style = textStyle(size);
    final l = layout(size);
    return Semantics(
      label: 'Movera',
      excludeSemantics: true,
      child: SizedBox(
        width: l.size.width,
        height: l.size.height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: l.mLeft,
              top: 0,
              child: Text('M', style: style),
            ),
            Positioned(
              left: l.pinRect.left,
              top: l.pinRect.top,
              child: Opacity(
                opacity: pinOpacity.clamp(0.0, 1.0),
                child: CustomPaint(
                  size: l.pinRect.size,
                  painter: const _PinPainter(),
                ),
              ),
            ),
            Positioned(
              left: l.veraLeft,
              top: 0,
              child: Text.rich(
                TextSpan(
                  text: 'v',
                  style: style,
                  children: [
                    TextSpan(
                      text: 'era',
                      style: style.copyWith(color: AuthColors.green),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MoveraWordmarkLayout {
  const MoveraWordmarkLayout({
    required this.size,
    required this.baseline,
    required this.mLeft,
    required this.veraLeft,
    required this.pinRect,
  });

  final Size size;
  final double baseline;
  final double mLeft;
  final double veraLeft;

  /// The pin's box, relative to the wordmark's top-left corner.
  final Rect pinRect;
}

/// The Movera map pin: its geometry, shared by the wordmark and the balloon
/// that becomes it in the sign-in intro.
abstract final class MoveraPin {
  /// Design canvas of [outline]: 32 wide, 42 tall, head centred at (16, 16).
  static const designSize = Size(32, 42);
  static const headCentre = Offset(16, 16);
  static const headRadius = 15.0;
  static const holeRadius = 7.5;

  /// Urbanist ExtraBold, measured: the x-height as a share of the font size.
  static const xHeight = 0.511;

  /// How far under the baseline the tip ends, as a share of the font size.
  static const tipBelowBaseline = 0.17;

  /// Pin height as a share of the font size (x-height + tip overhang).
  static const height = xHeight + tipBelowBaseline;

  /// Width / height of the pin.
  static const aspect = 32 / 42;

  /// Air between the pin and its neighbouring letters, in font sizes.
  static const gap = 0.02;

  /// The pin outline on [designSize]. [tip] is the y of the point (42 for
  /// the finished pin; the balloon starts rounder, with a higher tip).
  static Path outline({double tip = 42}) => Path()
    ..moveTo(16, tip)
    ..cubicTo(8, 28, 1, 24, 1, 16)
    ..arcToPoint(const Offset(31, 16), radius: const Radius.circular(15))
    ..cubicTo(31, 24, 24, 28, 16, tip)
    ..close();

  /// The pin with its round hole cut out (even-odd, so it is a real hole on
  /// every renderer), on [designSize].
  static Path withHole({double tip = 42, double hole = holeRadius}) {
    final path = outline(tip: tip)..fillType = PathFillType.evenOdd;
    if (hole > 0) {
      path.addOval(Rect.fromCircle(center: headCentre, radius: hole));
    }
    return path;
  }

  /// The pin's colours: ink at the top running into green at the tip, one
  /// continuous gradient (owner round 3).
  static const topColor = AuthColors.ink;
  static const bottomColor = AuthColors.green;

  /// The fill of the pin on [designSize]: [top] at the head running into
  /// [bottom] at the tip, blended across the middle.
  static Paint fill({Color top = topColor, Color bottom = bottomColor}) =>
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [top, bottom],
          stops: const [0.3, 0.8],
        ).createShader(Offset.zero & designSize);

  /// Draws the finished pin scaled into [size].
  static void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(
      size.width / designSize.width,
      size.height / designSize.height,
    );
    canvas.drawPath(withHole(), fill());
    canvas.restore();
  }
}

class _PinPainter extends CustomPainter {
  const _PinPainter();

  @override
  void paint(Canvas canvas, Size size) => MoveraPin.paint(canvas, size);

  @override
  bool shouldRepaint(_PinPainter oldDelegate) => false;
}
