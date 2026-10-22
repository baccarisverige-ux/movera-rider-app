// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/constants/appassets.dart';
import 'package:movera_rider/core/constants/appcolors.dart';
import 'package:movera_rider/core/constants/appfontweight.dart';
import 'package:movera_rider/features/history/presentation/ride_history.dart';
import 'package:movera_rider/features/notifications/application/notification_navigation.dart';
import 'package:movera_rider/features/notifications/application/notifications_controller.dart';
import 'package:movera_rider/features/notifications/domain/notifications.dart';
import 'package:movera_rider/shared/design_system/movera_empty_state.dart';
import 'package:movera_rider/shared/widgets/custom_text_widget.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';
import 'package:movera_rider/shared/widgets/push_permission_primer.dart';
import 'package:movera_rider/shared/widgets/responsive_size.dart';
import 'package:movera_rider/shared/widgets/sizedbox_extention.dart';
import 'package:movera_rider/l10n/l10n.dart';

class NotificationScreen extends StatelessWidget {
  const NotificationScreen({
    super.key,
    this.controller,
    this.openRide,
    this.openHistory,
  });

  final NotificationsController? controller;
  final NotificationRideOpener? openRide;

  /// Where a tap on an ended ride goes (FLOW-18); defaults to Ride History.
  final void Function(BuildContext context)? openHistory;

  @override
  Widget build(BuildContext context) {
    final notificationController = controller ?? NotificationsController();

    return Scaffold(
      backgroundColor: AppColor.secondary,
      body: SizedBox(
        child: Column(
          children: [
            50.height,
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  tooltip: context.l10n.back,
                  icon: Icon(
                    Icons.arrow_back_rounded,
                    size: ResSize.h * 20,
                    color: AppColor.primary,
                  ),
                ),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: TextWidget(
                      text: context.l10n.notification,
                      color: AppColor.primary,
                      fontSize: 18,
                      fontWeight: fwSemiBold,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                const SizedBox(width: 48, height: 48),
              ],
            ),
            12.height,
            PushStatusBanner(gate: AppScope.instance.pushPermission),
            Expanded(
              child: StreamBuilder<List<AppNotification>>(
                stream: notificationController.watch(),
                initialData: notificationController.feed(),
                builder: (context, snapshot) {
                  final items = snapshot.data ?? const <AppNotification>[];
                  if (items.isEmpty) {
                    return MoveraEmptyState(
                      icon: Icons.notifications_none_rounded,
                      title: context.l10n.allCaughtUp,
                      message:
                          context.l10n.notificationsEmptyBody,
                    );
                  }
                  return ListView.builder(
                    padding: EdgeInsets.symmetric(horizontal: screenHorizPadding),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final notification = items[index];
                      return Padding(
                        padding: EdgeInsets.only(bottom: ResSize.h * 16),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () async {
                            notificationController.markRead(notification.messageId);
                            final rideId = notificationRideTarget(
                              rideId: notification.rideId,
                              deepLink: notification.deepLink,
                            );
                            if (rideId == null) return;
                            await openNotificationRide(
                              context,
                              rideId,
                              open: openRide,
                              onEnded: () => (openHistory ?? _openHistory)(
                                context,
                              ),
                            );
                          },
                          child: _buildNotificationCard(context, notification),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  static void _openHistory(BuildContext context) {
    Navigator.of(context).push(RightToLeftTransition(RideHistory()));
  }

  Widget _buildNotificationCard(
    BuildContext context,
    AppNotification notification,
  ) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResSize.w * 4,
        vertical: ResSize.h * 4,
      ),
      decoration: BoxDecoration(
        color: AppColor.secondary,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            offset: const Offset(0, 5),
            color: const Color(0xff000000).withValues(alpha: 0.08),
            blurRadius: 20,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: ResSize.w * 52,
            height: ResSize.w * 52,
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Image.asset(
                AppAssets.standard,
                color: AppColor.subtitle,
                height: ResSize.h * 24,
              ),
            ),
          ),
          8.width,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextWidget(
                  text: notification.title,
                  fontSize: 16,
                  fontWeight: fwMedium,
                  color: AppColor.primary,
                ),
                if (notification.subtitle.isNotEmpty) ...[
                  2.height,
                  TextWidget(
                    text: notification.subtitle,
                    fontSize: 14,
                    fontWeight: fwNormal,
                    color: AppColor.subtitle,
                  ),
                ],
              ],
            ),
          ),
          8.width,
          Row(
            children: [
              TextWidget(
                text: notification.time,
                fontSize: 12,
                fontWeight: fwNormal,
                color: AppColor.subtitle,
              ),
              if (!notification.read) ...[
                4.width,
                // rider-u130: the dot is not the only sign of a new one.
                Semantics(
                  label: context.l10n.notificationUnread,
                  child: Container(
                    width: ResSize.w * 8,
                    height: ResSize.w * 8,
                    decoration: BoxDecoration(
                      color: AppColor.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
