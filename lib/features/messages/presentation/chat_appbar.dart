import 'package:flutter/material.dart';
import 'package:movera_rider/core/constants/appassets.dart';
import 'package:movera_rider/core/constants/appcolors.dart';
import 'package:movera_rider/core/constants/appfontweight.dart';
import 'package:movera_rider/shared/widgets/custom_text_widget.dart';
import 'package:movera_rider/shared/widgets/responsive_size.dart';
import 'package:movera_rider/shared/widgets/sizedbox_extention.dart';
import 'package:movera_rider/shared/design_system/movera_toast.dart';
import 'package:movera_rider/l10n/l10n.dart';

class ChatAppBar extends StatelessWidget {
  const ChatAppBar({super.key, this.driverName});

  final String? driverName;

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
          // A long name ("Meddelanden" at 130 % text on a 320 px phone)
          // shrinks to fit instead of overflowing the leading area.
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: TextWidget(
                text: _title,
                color: AppColor.title,
                fontSize: 16,
                fontWeight: fwBold,
              ),
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          // No driver phone number exists without a backend, so say so rather
          // than offering a button that silently does nothing.
          onPressed: () =>
              MoveraToast.show(context, context.l10n.chatCallUnavailable),
          tooltip: context.l10n.chatCall,
          icon: Image.asset(
            AppAssets.phoneOutl,
            height: ResSize.h * 23,
            excludeFromSemantics: true,
          ),
        ),
        8.width,
      ],
    );
  }
}
