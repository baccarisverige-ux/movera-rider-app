import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/constants/appcolors.dart';
import 'package:movera_rider/features/finding_driver/presentation/searching_map_marks.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/shared/design_system/movera_sheet.dart';
import 'package:movera_rider/shared/design_system/tokens.dart';

/// Owner 2026-11-23 (L3, window version B): the compact "Dela din plats"
/// sheet opened from the grey rider marker. Resolves true on "Dela plats".
Future<bool> showShareLocationSheet(BuildContext context) async {
  final share = await MoveraSheet.show<bool>(
    context: context,
    builder: (sheet) => const MoveraSheet(child: ShareLocationSheet()),
  );
  return share ?? false;
}

class ShareLocationSheet extends StatelessWidget {
  const ShareLocationSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SafeArea(
      top: false,
      child: Padding(
        key: const ValueKey('share-location-sheet'),
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SharePinIllustration(),
            const SizedBox(height: 6),
            Text(
              l10n.fdShareTitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: MoveraTokens.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.fdShareBody,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: MoveraTokens.muted,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                key: const ValueKey('share-location-yes'),
                style: FilledButton.styleFrom(
                  backgroundColor: SearchingMarkColors.pill,
                  foregroundColor: Colors.white,
                  shape: const StadiumBorder(),
                  textStyle: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onPressed: () => Navigator.pop(context, true),
                child: Text(l10n.fdShareButton),
              ),
            ),
            TextButton(
              key: const ValueKey('share-location-no'),
              onPressed: () => Navigator.pop(context, false),
              style: TextButton.styleFrom(
                foregroundColor: MoveraTokens.muted,
                minimumSize: const Size(120, 44),
              ),
              child: Text(
                l10n.notNow,
                style: GoogleFonts.poppins(fontSize: 15),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Version B: a 56 px navy 3D pin with the static walking man inside; the
/// pin bobs 4 px every 1.6 s over a pulsing ground halo. Reduce motion:
/// still.
class SharePinIllustration extends StatefulWidget {
  const SharePinIllustration({super.key});

  @override
  State<SharePinIllustration> createState() => _SharePinIllustrationState();
}

class _SharePinIllustrationState extends State<SharePinIllustration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bob = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still) {
      _bob
        ..stop()
        ..value = 0;
    } else if (!_bob.isAnimating) {
      _bob.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _bob.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('share-location-pin'),
      width: 84,
      height: 72,
      child: AnimatedBuilder(
        animation: _bob,
        builder: (context, _) {
          final t = Curves.easeInOut.transform(_bob.value);
          return Stack(
            alignment: Alignment.topCenter,
            children: [
              Positioned(
                bottom: 2,
                child: Container(
                  width: 44 + 14 * t,
                  height: 8,
                  decoration: BoxDecoration(
                    color: AppColor.blue.withValues(alpha: 0.16 - 0.06 * t),
                    borderRadius: const BorderRadius.all(
                      Radius.elliptical(40, 6),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 4 * t,
                child: const SizedBox(
                  width: 56,
                  height: 64,
                  child: CustomPaint(painter: _PinPainter()),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PinPainter extends CustomPainter {
  const _PinPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final r = w * 0.42;
    final c = Offset(w / 2, r + 2);
    final path = Path()
      ..moveTo(w / 2, size.height - 4)
      ..quadraticBezierTo(w / 2 - r * 0.55, c.dy + r * 0.85, c.dx - r, c.dy)
      ..arcToPoint(Offset(c.dx + r, c.dy), radius: Radius.circular(r))
      ..quadraticBezierTo(
        w / 2 + r * 0.55,
        c.dy + r * 0.85,
        w / 2,
        size.height - 4,
      )
      ..close();
    canvas
      ..drawPath(
        path.shift(const Offset(0, 2)),
        Paint()
          ..color = const Color(0x33061B44)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      )
      ..drawPath(
        path,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2D5878), AppColor.navy],
          ).createShader(Offset.zero & size),
      )
      ..drawCircle(c, r * 0.68, Paint()..color = Colors.white)
      ..drawCircle(c, r * 0.56, Paint()..color = AppColor.blue);
    final man = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(Icons.directions_walk_rounded.codePoint),
        style: TextStyle(
          fontFamily: Icons.directions_walk_rounded.fontFamily,
          fontSize: r * 0.8,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    man.paint(canvas, c - Offset(man.width / 2, man.height / 2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
