
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/auth/presentation/widgets/auth_style.dart';

/// Logo Movera avec couleurs adaptées au thème sélectionné.
/// Ocean Premium : bleu nuit et turquoise.
/// Eco Chic : vert forêt et sauge.
class MoveraWordmark extends StatelessWidget {
  const MoveraWordmark({super.key, this.size = 27});

  final double size;

  @override
  Widget build(BuildContext context) {
    final style = GoogleFonts.poppins(
      fontSize: size,
      height: 1,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.8,
      color: AuthColors.ink,
    );

    return Semantics(
      label: 'Movera',
      excludeSemantics: true,
      child: Text.rich(
        TextSpan(
          style: style,
          children: [
            const TextSpan(text: 'M'),

            // L'épingle représente le "o".
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: size * 0.03,
                ),
                child: Transform.translate(
                  offset: Offset(0, size * 0.16),
                  child: CustomPaint(
                    size: Size(size * 0.52, size * 0.7),

                    // Couleur d'accent du thème sélectionné.
                    painter: const _PinPainter(AuthColors.green),
                  ),
                ),
              ),
            ),

            const TextSpan(text: 'v'),

            // "era" prend la couleur d'accent du thème.
            TextSpan(
              text: 'era',
              style: style.copyWith(
                color: AuthColors.green,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Épingle de localisation avec un trou rond.
/// Elle conserve la forme originale du logo.
class _PinPainter extends CustomPainter {
  const _PinPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final r = w / 2;

    final pin = Path()
      ..fillType = PathFillType.evenOdd
      ..moveTo(r, h)
      ..cubicTo(r * 0.55, h * 0.8, 0, h * 0.55, 0, r)
      ..arcToPoint(
        Offset(w, r),
        radius: Radius.circular(r),
      )
      ..cubicTo(w, h * 0.55, r * 1.45, h * 0.8, r, h)
      ..close()
      ..addOval(
        Rect.fromCircle(
          center: Offset(r, r),
          radius: r * 0.42,
        ),
      );

    canvas.drawPath(
      pin,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_PinPainter oldDelegate) =>
      oldDelegate.color != color;
}
