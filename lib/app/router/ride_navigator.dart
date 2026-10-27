import 'dart:async';

import 'package:flutter/material.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/navigator_key.dart';
import 'package:movera_rider/app/router/routes.dart';
import 'package:movera_rider/core/web/web_overlay.dart';
import 'package:movera_rider/features/ride_booking/application/ride_restore_coordinator.dart';
import 'package:movera_rider/features/ride_booking/application/sheet_coordinator.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_transition.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';

abstract final class RideNavigator {
  static Future<dynamic> bottomToTop(BuildContext context, Widget page) {
    return Navigator.push(context, BottomToTopTransition(page));
  }

  static Future<dynamic> rightToLeft(BuildContext context, Widget page) {
    return Navigator.push(context, RightToLeftTransition(page));
  }

  static void home(
    BuildContext? context, {
    RideStatus status = RideStatus.cancelledByRider,
  }) {
    final ride = AppScope.instance.ride;
    if (ride.status != status) {
      if (canTransition(ride.status, status)) {
        ride.localTransition(status);
      } else if (status.isTerminal &&
          status != RideStatus.cancelledByRider &&
          status != RideStatus.closed) {
        // Driver/system/no-driver/payment/expiry terminals are external truth.
        // Navigation may acknowledge them, but must not downgrade them into a
        // local transition just to get back Home.
        ride.backendReconcile(status, id: ride.rideId);
      }
    }
    SheetCoordinator.instance.current = RideSheet.none;
    setWebOverlayOpen(false);

    final nav =
        moveraNavigatorKey.currentState ??
        (context != null && context.mounted
            ? Navigator.maybeOf(context, rootNavigator: true)
            : null);

    void finish() {
      unawaited(RideSnapshotStore.clear());
      final coordinator = RideRestoreCoordinator.instance;
      final rootWasRestoredRide = coordinator.showing != RestoredSurface.home;
      coordinator.goHome(replaceRoot: rootWasRestoredRide);
      final atRoot = nav == null || !nav.canPop();
      setWebHomeLock(atRoot);
    }

    if (nav == null) {
      finish();
      return;
    }

    // Finding/Waiting set PopScope.canPop via `_leaving` before this.
    // Pop now if unlocked; otherwise wait one frame. Never removeRoute:
    // on Flutter web that leaves the old ride in history, so Home bounces back.
    void popToRoot() {
      if (nav.canPop()) {
        nav.popUntil(AppRoutes.isHomeRoute);
      }
      finish();
    }

    if (nav.canPop()) {
      popToRoot();
    } else {
      // P5-R1: a post-frame callback does not ask for a frame. A restored
      // ride is the root (nothing to pop) and its screen can be still, so
      // on the web the rider stayed on the ended ride until a repaint.
      WidgetsBinding.instance
        ..addPostFrameCallback((_) => popToRoot())
        ..ensureVisualUpdate();
    }
  }

  static const names = AppRoutes;
}
