
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/auth/presentation/widgets/auth_style.dart';

/// Animated Movera logo.
/// Colours automatically follow the selected authentication theme.
/// The balloon rises and becomes the location pin ("o").
class BalloonBrandIntro extends StatelessWidget {
  const BalloonBrandIntro({
    super.key,
    required this.progress,
  });

  final Animation<double> progress;

  static double _phase(
    double value,
    double start,
    double end,
  ) =>
      ((value - start) / (end - start))
          .clamp(0.0, 1.0)
          .toDouble();

  @override
  Widget build(BuildContext context) {
    final reducedMotion =
        MediaQuery.of(context).disableAnimations;

    // Automatically uses Ocean Premium or Eco Chic.
    final brandStyle = GoogleFonts.poppins(
      fontSize: 37,
      height: 1,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.8,
      color: AuthColors.ink,
    );

    return Semantics(
      label: 'Movera. Moving to a new era.',
      child: ExcludeSemantics(
        child: SizedBox(
          height: 142,
          child: Center(
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(maxWidth: 350),
              child: LayoutBuilder(
                builder: (context, constraints) =>
                    AnimatedBuilder(
                  animation: progress,
                  builder: (context, _) {
                    final time = reducedMotion
                        ? 1.0
                        : progress.value;

                    final width =
                        constraints.maxWidth;
                    final center = width / 2;

                    final rise = Curves.easeInOutCubic
                        .transform(
                      _phase(time, 0.54, 0.78),
                    );

                    final originX =
                        width * 0.72 - 16;
                    final targetX = center - 43;

                    final balloonX = originX +
                        (targetX - originX) * rise;

                    final balloonY =
                        119 + (47 - 119) * rise;

                    final balloonOpacity =
                        _phase(time, 0.51, 0.56);

                    final morph = Curves.easeOut
                        .transform(
                      _phase(time, 0.72, 0.86),
                    );

                    final originalOOpacity =
                        1 - _phase(time, 0.70, 0.78);

                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          left: center - 80,
                          top: 43,
                          child: Text(
                            'M',
                            style: brandStyle,
                          ),
                        ),

                        Positioned(
                          left: center - 10,
                          top: 43,
                          child: Text(
                            'vera',
                            style: brandStyle,
                          ),
                        ),

                        // Original pin before animation.
                        Positioned(
                          left: targetX,
                          top: 47,
                          child: Opacity(
                            opacity:
                                originalOOpacity,
                            child: CustomPaint(
                              size:
                                  const Size(32, 42),
                              painter:
                                  const _PinBalloonPainter(
                                shape: 1,
                                placeholder: true,
                              ),
                            ),
                          ),
                        ),

                        // Animated balloon becomes pin.
                        Positioned(
                          left: balloonX,
                          top: balloonY,
                          child: Opacity(
                            opacity:
                                balloonOpacity,
                            child: CustomPaint(
                              size:
                                  const Size(32, 42),
                              painter:
                                  _PinBalloonPainter(
                                shape: morph,
                              ),
                            ),
                          ),
                        ),

                        Positioned(
                          left: 0,
                          right: 0,
                          top: 98,
                          child: Text(
                            'Moving to a new era.',
                            textAlign:
                                TextAlign.center,
                            maxLines: 1,
                            style:
                                GoogleFonts.poppins(
                              fontSize: 24,
                              height: 1.2,
                              fontWeight:
                                  FontWeight.w500,
                              letterSpacing: -0.5,
                              color:
                                  AuthColors.deepGreen,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Four-colour location pin using colours from the
/// selected theme instead of Google's original palette.
class _PinBalloonPainter extends CustomPainter {
  const _PinBalloonPainter({
    required this.shape,
    this.placeholder = false,
  });

  final double shape;
  final bool placeholder;

  // Changes automatically with AuthColors.
  static const List<Color> _colors = [
    AuthColors.ink,
    AuthColors.green,
    AuthColors.deepGreen,
    AuthColors.green,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    const center = Offset(16, 16);
    final tip = 31 + 11 * shape;

    final outline = Path()
      ..moveTo(16, tip)
      ..cubicTo(8, 28, 1, 24, 1, 16)
      ..arcToPoint(
        const Offset(31, 16),
        radius: const Radius.circular(15),
      )
      ..cubicTo(31, 24, 24, 28, 16, tip)
      ..close();

    if (placeholder) {
      canvas.drawPath(
        outline,
        Paint()..color = AuthColors.green,
      );
    } else {
      canvas.save();
      canvas.clipPath(outline);

      for (var i = 0; i < 4; i++) {
        canvas.drawRect(
          Rect.fromLTWH(
            (i.isOdd ? 16 : 0).toDouble(),
            (i >= 2 ? 16 : 0).toDouble(),
            16,
            30,
          ),
          Paint()..color = _colors[i],
        );
      }

      canvas.restore();
    }

    // Transparent-looking centre of the pin.
    if (shape > 0) {
      canvas.drawCircle(
        center,
        7.5 * shape,
        Paint()..color = AuthColors.ground,
      );
    }

    if (!placeholder && shape < 1) {
      canvas.drawPath(
        Path()
          ..moveTo(16, tip)
          ..quadraticBezierTo(
            19,
            37,
            16,
            42,
          ),
        Paint()
          ..color = AuthColors.muted
              .withValues(alpha: 1 - shape)
          ..strokeWidth = 1.2
          ..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(
    _PinBalloonPainter oldDelegate,
  ) =>
      oldDelegate.shape != shape ||
      oldDelegate.placeholder != placeholder;
}
