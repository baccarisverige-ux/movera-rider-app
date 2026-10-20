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
  const PromotionTicket({super.key, required this.promotion, this.onTap});

  static const Color _ink = Color(0xFF1D252C);
  static const Color _muted = Color(0xFF5C656C);

  final RiderPromotion promotion;
  final VoidCallback? onTap;

  static double get height => A11y.minTap + 2;

  @override
  Widget build(BuildContext context) {
    final left = promotion.ridesLeft;
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
            onTap:
                onTap ?? () => PromotionDetailsSheet.open(context, promotion),
            borderRadius: BorderRadius.circular(15),
            child: ExcludeSemantics(
              child: Padding(
                padding: EdgeInsets.only(
                  left: ResSize.w * 11,
                  right: ResSize.w * 14,
                ),
                child: Row(
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
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
