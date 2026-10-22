import 'package:flutter/material.dart';
import 'package:movera_rider/core/constants/appfontweight.dart';
import 'package:movera_rider/shared/design_system/movera_hit_area.dart';
import 'package:movera_rider/shared/design_system/tokens.dart';
import 'package:movera_rider/shared/widgets/app_icon_asset.dart';
import 'package:movera_rider/shared/widgets/responsive_size.dart';
import 'package:movera_rider/shared/widgets/sizedbox_extention.dart';

/// One item in Home's bottom nav bar (Home / Wallet / Reservations / Account).
class PremiumBottomNavItem extends StatelessWidget {
  const PremiumBottomNavItem({
    super.key,
    required this.iconAsset,
    required this.label,
    required this.onTap,
    this.active = false,
    this.floatingFraction = 0,
    this.hitSlop = 0,
    this.drawActiveBackground = true,
  });

  static const Color _premiumInk = MoveraTokens.ink;

  final String iconAsset;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final double floatingFraction;

  /// UI-4: transparent space above and below the item that still takes the
  /// tap (the floating bar's own padding), so the target is taller than the
  /// drawn item.
  final double hitSlop;

  /// False when a sliding selection (the liquid glass capsule) is drawn
  /// behind the items instead of each active item's own grey pill.
  final bool drawActiveBackground;

  @override
  Widget build(BuildContext context) {
    final activeColor = Color.lerp(
      const Color(0xFF2A7A84),
      _premiumInk,
      floatingFraction,
    )!;
    // UI-6: the inactive grey was 0xFF899197 (3.20:1 on white).
    final color = active ? activeColor : MoveraTokens.subtle;

    return MoveraHitArea(
      label: label,
      selected: active,
      onTap: onTap,
      minWidth: 0,
      minHeight: 0,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: hitSlop),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            excludeFromSemantics: true,
            borderRadius: BorderRadius.circular(24),
            child: Container(
              height: ResSize.h * 52,
              margin: EdgeInsets.symmetric(
                horizontal: ResSize.w * 2.5 * floatingFraction,
              ),
              decoration: BoxDecoration(
                color: active && drawActiveBackground
                    ? Color.lerp(
                        Colors.transparent,
                        const Color(0xFFF2F2F2),
                        floatingFraction,
                      )
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(
                  24 * floatingFraction + 14 * (1 - floatingFraction),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // UI-9: on short landscape or large text the icon box gives
                  // way instead of pushing the label out of the fixed height.
                  Flexible(
                    child: SizedBox(
                      height: ResSize.h * 30,
                      width: ResSize.w * 30,
                      child: Center(
                        child: AppIconAsset(
                          iconAsset,
                          size: ResSize.w * 22,
                          color: color,
                        ),
                      ),
                    ),
                  ),
                  2.height,
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: ResSize.w * 2),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      // UI-8: no text-scale clamp; the icon box gives way.
                      style: TextStyle(
                        color: color,
                        fontSize: ResSize.setSp(9.5),
                        fontWeight: active ? fwSemiBold : fwMedium,
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
