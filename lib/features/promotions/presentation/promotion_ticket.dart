import 'package:flutter/material.dart';
import 'package:movera_rider/core/constants/appassets.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/constants/appcolors.dart';
import 'package:movera_rider/core/constants/appfontweight.dart';
import 'package:movera_rider/features/promotions/application/rider_promotion_controller.dart';
import 'package:movera_rider/features/promotions/presentation/promotion_details_sheet.dart';
import 'package:movera_rider/shared/accessibility/a11y.dart';
import 'package:movera_rider/shared/widgets/custom_text_widget.dart';
import 'package:movera_rider/shared/widgets/responsive_size.dart';
import 'package:movera_rider/shared/widgets/sizedbox_extention.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// The promotion ticket shown on top of the Home sheet and the ride list.
///
/// It has no close button: it stays while the rider has the promotion and
/// disappears when the rides are used or the promotion ends. Tapping it opens
/// the details.
class PromotionTicket extends StatelessWidget {
  const PromotionTicket({
    super.key,
    required this.promotion,
    this.onTap,
    this.flat = false,
  });

  static const Color _ink = Color(0xFF1D252C);
  static const Color _muted = Color(0xFF5C656C);

  final RiderPromotion promotion;
  final VoidCallback? onTap;

  /// Owner round 1 ("simple row", Home sheet only): the car, the title and
  /// "{n} left" in one row, with no border, background, shadow or rounded
  /// box, and no side inset of its own, so it lines up with the sheet's
  /// content. Same height, tap and semantics as the ticket.
  final bool flat;

  static double get height => A11y.minTap + 2;

  @override
  Widget build(BuildContext context) {
    final left = promotion.ridesLeft;
    final row = Row(
      children: [
        SizedBox(
          width: ResSize.w * 45,
          height: ResSize.h * 34,
          child: Image.asset(
            AppAssets.promoCard,
            width: ResSize.w * 43,
            height: ResSize.h * 31,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
        ),
        8.width,
        Expanded(
          child: Text(
            promotion.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
              fontSize: ResSize.setSp(12.2),
              fontWeight: fwSemiBold,
              color: _ink,
            ),
          ),
        ),
        8.width,
        TextWidget(
          text: context.l10n.nLeft('$left'),
          color: _muted,
          fontSize: 11,
          fontWeight: fwMedium,
        ),
      ],
    );
    final open = onTap ?? () => PromotionDetailsSheet.open(context, promotion);
    if (flat) {
      return Semantics(
        button: true,
        label: '${promotion.title}. ${context.l10n.ridesLeft(left)}',
        child: Material(
          key: const ValueKey('promotion-row-flat'),
          type: MaterialType.transparency,
          child: InkWell(
            onTap: open,
            child: SizedBox(
              height: height,
              child: ExcludeSemantics(child: row),
            ),
          ),
        ),
      );
    }
    return Semantics(
      button: true,
      label: '${promotion.title}. ${context.l10n.ridesLeft(left)}',
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: AppColor.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: const Color(0xFFDDE2E4), width: 0.9),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF142D39).withValues(alpha: 0.09),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: open,
            borderRadius: BorderRadius.circular(15),
            child: ExcludeSemantics(
              child: Padding(
                padding: EdgeInsets.only(
                  left: ResSize.w * 11,
                  right: ResSize.w * 14,
                ),
                child: row,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
