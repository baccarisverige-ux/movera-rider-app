import 'package:flutter/material.dart';
import 'package:movera_rider/core/constants/appcolors.dart';
import 'package:movera_rider/core/constants/appfontweight.dart';
import 'package:movera_rider/features/home/presentation/widgets/home_sheet_layout.dart';
import 'package:movera_rider/shared/widgets/custom_text_widget.dart';
import 'package:movera_rider/shared/widgets/responsive_size.dart';
import 'package:movera_rider/shared/widgets/sizedbox_extention.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// The "Plan ahead. Ride on time." schedule-a-ride promo card.
class AdvanceBookingCard extends StatelessWidget {
  const AdvanceBookingCard({super.key, required this.onOpenSchedule});

  static const Color _premiumInk = Color(0xFF1D252C);
  static const Color _premiumMuted = Color(0xFF5C656C);
  static const Color _premiumLine = Color(0xFFE7EBEE);
  static const Color _premiumAccent = Color(0xFF2D5878);

  final VoidCallback onOpenSchedule;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onOpenSchedule,
      borderRadius: BorderRadius.circular(HomeSheetLayout.cardRadius),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(
          ResSize.w * 12,
          ResSize.h * 12,
          ResSize.w * 12,
          ResSize.h * 12,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFA),
          borderRadius: BorderRadius.circular(HomeSheetLayout.cardRadius),
          border: Border.all(color: _premiumLine, width: 0.8),
          boxShadow: [
            BoxShadow(
              color: _premiumAccent.withValues(alpha: 0.06),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: SizedBox(
                width: double.infinity,
                height: ResSize.h * 88,
                child: Image.asset(
                  excludeFromSemantics: true,
                  'assets/images/advance_booking_driver.webp',
                  fit: BoxFit.cover,
                  alignment: const Alignment(0, -0.28),
                  filterQuality: FilterQuality.high,
                  cacheWidth: 800,
                ),
              ),
            ),
            8.height,
            TextWidget(
              text: context.l10n.advancePlanAhead,
              color: _premiumInk,
              fontSize: 15.5,
              fontWeight: fwBold,
            ),
            4.height,
            Padding(
              padding: EdgeInsets.symmetric(horizontal: ResSize.w * 8),
              child: TextWidget(
                text: context.l10n.advanceBody,
                color: _premiumMuted,
                fontSize: 11,
                fontWeight: fwNormal,
                textAlign: TextAlign.center,
              ),
            ),
            8.height,
            Container(
              height: ResSize.h * 38,
              width: double.infinity,
              decoration: BoxDecoration(
                color: _premiumAccent,
                borderRadius: BorderRadius.circular(16),
              ),
              alignment: Alignment.center,
              child: TextWidget(
                text: context.l10n.scheduleARide,
                color: AppColor.white,
                fontSize: 12.5,
                fontWeight: fwSemiBold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
