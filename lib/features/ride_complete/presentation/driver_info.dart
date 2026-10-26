import 'package:flutter/material.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/constants/appcolors.dart';
import 'package:movera_rider/core/constants/appfontweight.dart';
import 'package:movera_rider/shared/design_system/movera_empty_state.dart';
import 'package:movera_rider/shared/formatters/name_format.dart';
import 'package:movera_rider/shared/widgets/custom_text_widget.dart';
import 'package:movera_rider/shared/widgets/responsive_size.dart';
import 'package:movera_rider/shared/widgets/sizedbox_extention.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Riders recognise a trip by when it happened, not by a database key. Keep a
/// short tail so support can still match it to the full id.
String _reference(String rideId) {
  final trimmed = rideId.trim();
  if (trimmed.isEmpty) return '';
  final tail = trimmed.length <= 6
      ? trimmed
      : trimmed.substring(trimmed.length - 6);
  return '#${tail.toUpperCase()}';
}

class RideCompletedDriverInfo extends StatelessWidget {
  const RideCompletedDriverInfo({super.key, this.rideId});

  /// The ride this screen completes; another ride's driver is never shown.
  final String? rideId;

  @override
  Widget build(BuildContext context) {
    final driver = AppScope.instance.rideComplete.driver(rideId: rideId);
    if (driver == null) {
      return MoveraEmptyState(
        icon: Icons.person_search_outlined,
        title: context.l10n.driverDetailsUnavailable,
        message: context.l10n.driverDetailsUnavailableReceipt,
        compact: true,
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: screenHorizPadding),
      child: Column(
        children: [
          Container(
            height: ResSize.h * 74,
            width: ResSize.h * 74,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Color(0xFFE8F0F6),
              shape: BoxShape.circle,
            ),
            child: TextWidget(
              text: initialFromName(driver.name, whenEmpty: '?'),
              color: const Color(0xFF2D5878),
              fontSize: 28,
              fontWeight: fwSemiBold,
            ),
          ),
          14.height,
          Center(
            child: TextWidget(
              text: driver.name,
              color: AppColor.title,
              fontSize: 20,
              fontWeight: fwSemiBold,
            ),
          ),
          2.height,
          Center(
            child: TextWidget(
              text: driver.vehicle,
              color: AppColor.title,
              fontSize: 14,
              fontWeight: fwMedium,
            ),
          ),
          24.height,
          Row(
            children: [
              Expanded(
                child: TextWidget(
                  text: context.l10n.tripCompleted,
                  color: AppColor.title,
                  fontSize: 14,
                  fontWeight: fwMedium,
                ),
              ),
              const SizedBox(width: 12),
              // A raw ride id is for support, not for the rider, and a full
              // one ran straight through its own label. Show a short reference.
              Flexible(
                child: TextWidget(
                  text: _reference(driver.rideNumber),
                  color: AppColor.subtitle,
                  fontSize: 14,
                  fontWeight: fwMedium,
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
          8.height,
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextWidget(
                  text: context.l10n.dateAndTime,
                  color: AppColor.title,
                  fontSize: 14,
                  fontWeight: fwMedium,
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: TextWidget(
                  text: driver.completedAt,
                  color: AppColor.subtitle,
                  fontSize: 14,
                  fontWeight: fwMedium,
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
          8.height,
        ],
      ),
    );
  }
}
