import 'package:flutter/material.dart';
import 'package:movera_rider/shared/accessibility/a11y.dart';
import 'package:movera_rider/shared/design_system/movera_hit_area.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Home's top-right capsule (saved-places design step 1, owner 2026-11-18:
/// B11 "clear glass" at 85 %, menu left, places button P3 = a blue round
/// push-pin and a small down arrow in a grey chip; mock/B11-bluepin.png).
/// Step 8: the profile button is gone; the profile is under "Konto".
/// While the places pop-up is open ([placesOpen]) the chip turns black and
/// the arrow points up (step 2, mock/step2-popup.png P2-3).
class PremiumTopActions extends StatelessWidget {
  const PremiumTopActions({
    super.key,
    required this.onMenuTap,
    required this.onPlacesTap,
    this.placesOpen = false,
  });

  /// The capsule is drawn at this scale (approved footprint on Home).
  static const double _scale = 0.82;
  static const Color ink = Color(0xFF111614);
  static const Color pinBlue = Color(0xFF1A73E8);

  final VoidCallback onMenuTap;
  final VoidCallback onPlacesTap;
  final bool placesOpen;

  @override
  Widget build(BuildContext context) {
    final capsule = Transform.scale(
      scale: _scale,
      alignment: Alignment.topRight,
      child: ExcludeSemantics(
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: ink.withValues(alpha: 0.16),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            // No BackdropFilter: the map under it is a platform view that a
            // blur cannot sample, and Home bans BackdropFilter over the map
            // (audit_fix_home_sheet_wash_test); 85 % white stays.
            child: Container(
              key: const ValueKey('home-top-capsule'),
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.white.withValues(alpha: 0.8)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Tap(
                    key: const ValueKey('home-menu'),
                    onTap: onMenuTap,
                    child: const SizedBox(
                      width: 48,
                      height: 48,
                      child: Icon(Icons.menu_rounded, size: 24, color: ink),
                    ),
                  ),
                  _Tap(
                    key: const ValueKey('home-places'),
                    onTap: onPlacesTap,
                    // 48 x 48 or more to tap; the chip drawn is 44 high.
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minWidth: 48),
                        child: _PlacesChip(open: placesOpen),
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
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: 0,
          right: 0,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _target(context.l10n.menu, onMenuTap),
              _target(context.l10n.menuSavedPlaces, onPlacesTap),
            ],
          ),
        ),
        capsule,
      ],
    );
  }

  Widget _target(String label, VoidCallback onTap) {
    return MoveraHitArea(
      label: label,
      onTap: onTap,
      minWidth: A11y.minTap,
      minHeight: A11y.minTap,
      child: const SizedBox.shrink(),
    );
  }
}

class _Tap extends StatelessWidget {
  const _Tap({super.key, required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        excludeFromSemantics: true,
        borderRadius: BorderRadius.circular(22),
        child: child,
      ),
    );
  }
}

/// P3: grey chip, blue push-pin, small arrow; black with the arrow up while
/// the pop-up is open.
class _PlacesChip extends StatelessWidget {
  const _PlacesChip({required this.open});

  final bool open;

  @override
  Widget build(BuildContext context) {
    const ink = PremiumTopActions.ink;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      height: 44,
      padding: const EdgeInsets.fromLTRB(11, 0, 9, 0),
      decoration: BoxDecoration(
        color: open ? ink : ink.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: ink.withValues(alpha: 0.14)),
        boxShadow: open
            ? [
                BoxShadow(
                  color: ink.withValues(alpha: 0.30),
                  blurRadius: 9,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CustomPaint(
            size: const Size(16, 26),
            painter: PushPinPainter(
              needle: open ? const Color(0xFFE8EEF1) : const Color(0xFF5A6B75),
            ),
          ),
          const SizedBox(width: 1),
          Icon(
            open
                ? Icons.keyboard_arrow_up_rounded
                : Icons.keyboard_arrow_down_rounded,
            key: ValueKey(open ? 'home-places-up' : 'home-places-down'),
            size: 17,
            color: open ? Colors.white : ink,
          ),
        ],
      ),
    );
  }
}

/// The round blue push-pin (#1A73E8, lit from the top left) with its needle.
class PushPinPainter extends CustomPainter {
  const PushPinPainter({this.color = PremiumTopActions.pinBlue, this.needle});

  final Color color;
  final Color? needle;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.height / 24;
    final cx = size.width / 2;
    canvas.drawLine(
      Offset(cx, 13 * s),
      Offset(cx, 23 * s),
      Paint()
        ..color = needle ?? const Color(0xFF5A6B75)
        ..strokeWidth = 1.7 * s
        ..strokeCap = StrokeCap.round,
    );
    final head = Offset(cx, 7.2 * s);
    final r = 6.6 * s;
    canvas.drawCircle(
      head,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.28, -0.40),
          radius: 0.75,
          colors: [
            Color.lerp(color, Colors.white, 0.5)!,
            color,
            Color.lerp(color, Colors.black, 0.3)!,
          ],
          stops: const [0, 0.45, 1],
        ).createShader(Rect.fromCircle(center: head, radius: r)),
    );
    canvas.save();
    canvas.translate(head.dx - 2.2 * s, head.dy - 2.4 * s);
    canvas.rotate(-0.61);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 3.8 * s, height: 2.6 * s),
      Paint()..color = Colors.white.withValues(alpha: 0.55),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(PushPinPainter old) =>
      old.color != color || old.needle != needle;
}
