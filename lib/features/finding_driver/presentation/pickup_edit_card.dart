import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/constants/appassets.dart';
import 'package:movera_rider/core/constants/appcolors.dart';
import 'package:movera_rider/features/finding_driver/presentation/searching_map_marks.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/shared/design_system/tokens.dart';
import 'package:movera_rider/shared/formatters/money.dart';
import 'package:movera_rider/shared/widgets/app_icon_asset.dart';

/// Owner 2026-11-23 (pe-C-a / pe-C-b): the compact bottom card of the
/// pickup edit mode while searching.
class PickupEditCard extends StatelessWidget {
  const PickupEditCard({
    super.key,
    required this.address,
    required this.onSearch,
    required this.onConfirm,
    this.oldPrice,
    this.newPrice,
    this.currency = 'SEK',
    this.busy = false,
  });

  final String address;
  final VoidCallback onSearch;
  final VoidCallback? onConfirm;

  /// Both set when the pin is beyond the free zone and priced.
  final double? oldPrice;
  final double? newPrice;
  final String currency;
  final bool busy;

  bool get _priced => oldPrice != null && newPrice != null;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      key: const ValueKey('pickup-edit-card'),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(MoveraTokens.radiusSheet),
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x1F162C36),
            blurRadius: 24,
            offset: Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: MoveraTokens.line,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              l10n.liveAdjustPickupButton,
              style: GoogleFonts.poppins(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: MoveraTokens.ink,
              ),
            ),
            Text(
              l10n.fdAdjustSubtitle,
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: MoveraTokens.muted,
              ),
            ),
            const SizedBox(height: 10),
            const Divider(height: 1, color: MoveraTokens.line),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                children: [
                  Container(
                    height: 48,
                    padding: const EdgeInsets.only(left: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F7),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        const AppIconAsset(
                          AppAssets.solarMapPoint,
                          size: 20,
                          color: AppColor.navy,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            address,
                            key: const ValueKey('pickup-edit-address'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              fontSize: 15,
                              color: MoveraTokens.ink,
                            ),
                          ),
                        ),
                        IconButton(
                          key: const ValueKey('pickup-edit-search'),
                          tooltip: l10n.fdSearchAddress,
                          onPressed: onSearch,
                          icon: const AppIconAsset(
                            AppAssets.solarSearch,
                            size: 20,
                            color: MoveraTokens.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_priced) ...[
                    const SizedBox(height: 8),
                    Text.rich(
                      key: const ValueKey('pickup-edit-price-line'),
                      TextSpan(
                        children: [
                          TextSpan(
                            text: formatMajor(oldPrice!, currency),
                            style: const TextStyle(
                              decoration: TextDecoration.lineThrough,
                              color: MoveraTokens.muted,
                            ),
                          ),
                          TextSpan(text: ' ${l10n.newPrice} '),
                          TextSpan(
                            text: formatMajor(newPrice!, currency),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColor.navy,
                            ),
                          ),
                        ],
                      ),
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: MoveraTokens.ink,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      key: const ValueKey('pickup-edit-confirm'),
                      style: FilledButton.styleFrom(
                        backgroundColor: SearchingMarkColors.pill,
                        foregroundColor: Colors.white,
                        shape: const StadiumBorder(),
                        textStyle: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onPressed: busy ? null : onConfirm,
                      child: busy
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              _priced
                                  ? l10n.confirmNewPrice
                                  : l10n.confirmPickup,
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The centred, lifted pin of the edit mode with its address bubble and,
/// beyond the free zone, the "+N kr" bubble. Blue inside the zone, navy
/// beyond it.
class PickupEditPin extends StatelessWidget {
  const PickupEditPin({
    super.key,
    required this.label,
    required this.beyond,
    this.extra,
  });

  final String label;
  final bool beyond;

  /// "+16 kr", beyond the zone once priced.
  final String? extra;

  @override
  Widget build(BuildContext context) {
    final colour = beyond ? AppColor.navy : AppColor.blue;
    // The pin's tip sits on the map centre: the widget is laid out so its
    // bottom centre (tip + shadow gap) is the centre of the parent.
    return IgnorePointer(
      child: SizedBox(
        key: const ValueKey('pickup-edit-pin'),
        width: 260,
        height: 120,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            Positioned(
              bottom: -6,
              child: Container(
                width: 18,
                height: 6,
                decoration: const BoxDecoration(
                  color: Color(0x40061B44),
                  borderRadius: BorderRadius.all(Radius.elliptical(9, 3)),
                ),
              ),
            ),
            Positioned(
              bottom: 8,
              child: Icon(Icons.location_on_rounded, size: 48, color: colour),
            ),
            Positioned(
              bottom: 58,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                constraints: const BoxConstraints(maxWidth: 240),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: const [
                    BoxShadow(color: Color(0x241B2733), blurRadius: 8),
                  ],
                ),
                child: Text(
                  label,
                  key: const ValueKey('pickup-edit-bubble'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: MoveraTokens.ink,
                  ),
                ),
              ),
            ),
            if (extra != null)
              Positioned(
                bottom: 18,
                left: 130 + 22,
                child: Container(
                  key: const ValueKey('pickup-edit-extra'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColor.navy,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    extra!,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
