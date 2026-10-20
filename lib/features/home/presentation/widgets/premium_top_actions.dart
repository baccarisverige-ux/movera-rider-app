import 'package:flutter/material.dart';
import 'package:movera_rider/core/constants/appcolors.dart';
import 'package:movera_rider/shared/accessibility/a11y.dart';
import 'package:movera_rider/shared/design_system/movera_hit_area.dart';
import 'package:movera_rider/shared/design_system/movera_icon_button.dart';
import 'package:movera_rider/shared/design_system/tokens.dart';
import 'package:movera_rider/shared/widgets/responsive_size.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// The menu/account pill in Home's top-right corner.
class PremiumTopActions extends StatelessWidget {
  const PremiumTopActions({
    super.key,
    required this.onMenuTap,
    required this.onAccountTap,
  });

  static const Color _premiumLine = MoveraTokens.line;

  /// The pill is drawn at this scale (approved design).
  static const double _scale = 0.82;

  final VoidCallback onMenuTap;
  final VoidCallback onAccountTap;

  @override
  Widget build(BuildContext context) {
    // UI-4: the scale used to shrink the buttons' hit areas to 39.4 px too.
    // The pill is still drawn scaled, but two unscaled 48 x 48 targets sit
    // under it (top-right, where the scaled pill is drawn), so a tap on the
    // pill's edge or just beside it still lands. The drawn buttons keep their
    // ripple and take the taps they cover.
    final pill = Transform.scale(
      scale: _scale,
      alignment: Alignment.topRight,
      child: ExcludeSemantics(
        child: Container(
          height: MoveraIconButton.minTap + 8,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColor.white.withValues(alpha: 0.99),
                const Color(0xFFF8FAFA).withValues(alpha: 0.98),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _premiumLine, width: 0.8),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF162C36).withValues(alpha: 0.13),
                blurRadius: 22,
                offset: const Offset(0, 7),
              ),
              BoxShadow(
                color: AppColor.white.withValues(alpha: 0.88),
                blurRadius: 2,
                offset: const Offset(0, -1),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PremiumTopAction(icon: Icons.menu_open_rounded, onTap: onMenuTap),
              Container(
                height: ResSize.h * 23,
                width: 0.8,
                color: _premiumLine,
              ),
              _PremiumTopAction(
                icon: Icons.person_rounded,
                onTap: onAccountTap,
              ),
            ],
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
              _target(context.l10n.navAccount, onAccountTap),
            ],
          ),
        ),
        pill,
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

class _PremiumTopAction extends StatelessWidget {
  const _PremiumTopAction({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        excludeFromSemantics: true,
        borderRadius: BorderRadius.circular(19),
        child: SizedBox(
          height: MoveraIconButton.minTap,
          width: MoveraIconButton.minTap,
          child: Icon(icon, size: 24, color: const Color(0xFF11181D)),
        ),
      ),
    );
  }
}
