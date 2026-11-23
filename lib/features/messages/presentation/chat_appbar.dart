import 'package:flutter/material.dart';
import 'package:movera_rider/core/constants/appassets.dart';
import 'package:movera_rider/core/constants/appcolors.dart';
import 'package:movera_rider/core/constants/appfontweight.dart';
import 'package:movera_rider/shared/widgets/custom_text_widget.dart';
import 'package:movera_rider/shared/widgets/responsive_size.dart';
import 'package:movera_rider/shared/widgets/sizedbox_extention.dart';
import 'package:movera_rider/shared/design_system/movera_toast.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/features/driver_arriving/presentation/driver_photo_avatar.dart';
import 'package:movera_rider/features/driver_profile/presentation/driver_on_way_card.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/matched_driver.dart';

class ChatAppBar extends StatelessWidget {
  const ChatAppBar({super.key, this.driverName, this.onCall, this.driver});

  final String? driverName;

  /// Owner 2026-11-23 (chat v2): photo and plate next to the name.
  final MatchedDriver? driver;

  /// The masked call (contract v0.13.0 §22). Null: calls are not available.
  final VoidCallback? onCall;

  String get _title {
    final name = driverName?.trim() ?? '';
    return name.isEmpty ? L10n.current.supportMessages : name;
  }

  @override
  Widget build(BuildContext context) {
    return AppBar(
      actionsPadding: EdgeInsets.all(0),
      automaticallyImplyLeading: false,
      backgroundColor: AppColor.white,
      clipBehavior: Clip.none,
      foregroundColor: AppColor.white,
      surfaceTintColor: Colors.transparent,
      leadingWidth: MediaQuery.of(context).size.width * 0.7,
      elevation: 0,
      shape: const Border(bottom: BorderSide(color: Color(0xFFE7EBEE))),
      leading: Row(
        children: [
          8.width,
          IconButton(
            onPressed: () {
              Navigator.pop(context);
            },
            tooltip: context.l10n.back,
            icon: Icon(
              Icons.arrow_back_rounded,
              color: AppColor.title,
              size: ResSize.h * 23,
            ),
          ),
          if (driver case final d?) ...[
            DriverPhotoAvatar(
              key: const ValueKey('chat-header-photo'),
              driver: d,
              radius: 20,
              fallback: Text(
                d.initial,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColor.navy,
                ),
              ),
            ),
            10.width,
          ],
          // A long name ("Meddelanden" at 130 % text on a 320 px phone)
          // shrinks to fit instead of overflowing the leading area.
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextWidget(
                    text: _title,
                    color: AppColor.title,
                    fontSize: 16,
                    fontWeight: fwBold,
                  ),
                  if (driver?.plate case final plate?) ...[
                    2.height,
                    SwedishPlate(text: plate, small: true),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
      actions: [
        // Owner 2026-11-23 (chat v2): a round outlined phone button.
        Tooltip(
          message: context.l10n.chatCall,
          child: Material(
            color: Colors.white,
            shape: const CircleBorder(
              side: BorderSide(color: Color(0xFFE7EBEE)),
            ),
            child: InkWell(
              key: const ValueKey('chat-call'),
              customBorder: const CircleBorder(),
              // Never the driver's real number: the masked call, or a line
              // saying calls are not available yet.
              onTap:
                  onCall ??
                  () => MoveraToast.show(
                    context,
                    context.l10n.chatCallUnavailable,
                  ),
              child: SizedBox.square(
                dimension: 48,
                child: Center(
                  child: Image.asset(
                    AppAssets.phoneOutl,
                    height: 21,
                    color: AppColor.navy,
                    excludeFromSemantics: true,
                  ),
                ),
              ),
            ),
          ),
        ),
        12.width,
      ],
    );
  }
}
