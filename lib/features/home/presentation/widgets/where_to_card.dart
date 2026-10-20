import 'package:flutter/material.dart';
import 'package:movera_rider/shared/widgets/app_icon_asset.dart';
import 'package:movera_rider/core/constants/appassets.dart';
import 'package:movera_rider/core/constants/appcolors.dart';
import 'package:movera_rider/core/constants/appfontweight.dart';
import 'package:movera_rider/features/home/presentation/widgets/short_address.dart';
import 'package:movera_rider/shared/widgets/custom_text_widget.dart';
import 'package:movera_rider/shared/widgets/responsive_size.dart';
import 'package:movera_rider/shared/widgets/sizedbox_extention.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// The "Where to? / Later" card on Home's collapsed sheet.
class WhereToCard extends StatelessWidget {
  const WhereToCard({
    super.key,
    required this.destinationAddress,
    required this.onDestinationTap,
    required this.onOpenSchedule,
  });

  static const Color _premiumInk = Color(0xFF1D252C);
  static const Color _premiumLine = Color(0xFFE7EBEE);

  final String? destinationAddress;
  final VoidCallback onDestinationTap;
  final VoidCallback onOpenSchedule;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: ResSize.h * 58,
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(ResSize.w * 4, 0, ResSize.w * 7, 0),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9F9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE8EDEF), width: 0.8),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF173B4D).withValues(alpha: 0.035),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        // UI-3: stretch both tap targets to the card's full height.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onDestinationTap,
                borderRadius: BorderRadius.circular(18),
                child: Semantics(
                  button: true,
                  excludeSemantics: true,
                  label: destinationAddress == null
                      ? context.l10n.whereTo
                      : context.l10n.destinationLabel(shortAddress(destinationAddress, maxLength: 28)),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: ResSize.w * 13),
                    child: Row(
                      children: [
                        Icon(
                          Icons.search_rounded,
                          size: ResSize.h * 26,
                          color: _premiumInk,
                        ),
                        12.width,
                        Expanded(
                          child: TextWidget(
                            text: destinationAddress == null
                                ? context.l10n.whereTo
                                : shortAddress(
                                    destinationAddress,
                                    maxLength: 28,
                                  ),
                            color: _premiumInk.withValues(alpha: 0.72),
                            fontSize: destinationAddress == null ? 16.5 : 12.5,
                            fontWeight: fwMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onOpenSchedule,
              borderRadius: BorderRadius.circular(18),
              child: Semantics(
                button: true,
                excludeSemantics: true,
                label: context.l10n.scheduleForLater,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  child: Center(
                    child: Container(
                      height: ResSize.h * 28.4,
                      padding: EdgeInsets.symmetric(horizontal: ResSize.w * 8),
                      decoration: BoxDecoration(
                        color: AppColor.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _premiumLine, width: 0.8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.045),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AppIconAsset(
                            AppAssets.solarCalendar,
                            size: ResSize.w * 18,
                            color: _premiumInk,
                          ),
                          4.width,
                          TextWidget(
                            text: context.l10n.later,
                            color: _premiumInk,
                            fontSize: 9.2,
                            fontWeight: fwSemiBold,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
