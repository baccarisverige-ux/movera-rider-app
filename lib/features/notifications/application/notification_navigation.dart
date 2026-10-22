import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/navigator_key.dart';
import 'package:movera_rider/app/router/routes.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/reservations/presentation/upcoming_reservation.dart';
import 'package:movera_rider/features/ride_booking/application/ride_restore_coordinator.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/shared/design_system/movera_toast.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';

typedef NotificationRideOpener = Future<bool> Function(String rideId);

/// Routes that already show the live ride; opening that ride's notification
/// keeps them (and their chat, rating or tip in progress) instead of
/// rebuilding the ride at the root.
const _rideStageRoutes = {
  AppRoutes.findingDriver,
  AppRoutes.waitingForDriver,
  AppRoutes.rideCompleted,
};

bool _rideOpenBusy = false;
bool _rowTapBusy = false;

/// True when nothing may open over the current screen: Sign in (or the new
/// rider name step) is the root, or a signed-in build has no session.
Future<bool> navigationBlockedBySignIn() async {
  if (RideRestoreCoordinator.instance.authRootShowing) return true;
  if (!AppEnv.current.authRequired) return false;
  final tokens = AppScope.instance.tokens;
  final access = await tokens.readAccess();
  final refresh = await tokens.readRefresh();
  return access?.isNotEmpty != true || refresh?.isNotEmpty != true;
}

/// The route currently on top. popUntil stops at once when the predicate is
/// true for the top route, so nothing is popped.
Route<dynamic>? _topRoute(NavigatorState nav) {
  Route<dynamic>? top;
  nav.popUntil((route) {
    top = route;
    return true;
  });
  return top;
}

/// Pushes the page named [name] unless Sign in is showing or that page is
/// already on top. Returns false when nothing can be opened.
bool pushPageOnce(Widget Function() page, String name) {
  final nav = moveraNavigatorKey.currentState;
  if (nav == null) return false;
  if (RideRestoreCoordinator.instance.authRootShowing) return false;
  if (_topRoute(nav)?.settings.name == name) return true;
  unawaited(
    nav.push<void>(
      RightToLeftTransition(page(), settings: RouteSettings(name: name)),
    ),
  );
  return true;
}

/// Opens what a ride notification points at. Returns false when there is
/// nothing to open (the ride has ended or is not this rider's current ride).
Future<bool> openRideFromNotification(String rideId) async {
  final expected = rideId.trim();
  if (expected.isEmpty) return false;
  // NAV-15: on a cold start from a push, let the gate's first restore land
  // before resuming, so the ride is not built twice (or over Sign in).
  await RideRestoreCoordinator.instance.firstRootResolved;
  // Handled on purpose: neither the ride nor the notification list may open
  // over Sign in.
  if (await navigationBlockedBySignIn()) return true;
  // A second tap or push while the first is still resyncing would pop and
  // swap the stack twice.
  if (_rideOpenBusy) return true;
  _rideOpenBusy = true;
  try {
    return await _openRide(expected);
  } finally {
    _rideOpenBusy = false;
  }
}

Future<bool> _openRide(String expected) async {
  await AppScope.instance.rideRealtime.reconnectAndResync(expected);

  // ARCH-12: a push for a ride this device never saved (second device,
  // cleared storage) asks the server for the rider's active trip.
  final snapshot = await RideSnapshotStore.read() ??
      await RideRestoreCoordinator.instance.adoptServerActiveTrip(
        expectedRideId: expected,
      );
  if (snapshot == null || snapshot.rideId?.trim() != expected) {
    return _openReservation(expected);
  }

  final surface = RideRestoreCoordinator.instance.surfaceFor(snapshot);
  if (surface == RestoredSurface.home) return false;

  // Another ride owns the visible search: do not tear it down.
  final owner = FindingDriverController.active?.ownedRideId;
  if (owner != null && owner.isNotEmpty && owner != expected) return false;

  final nav = moveraNavigatorKey.currentState;
  if (nav != null && nav.canPop()) {
    // Close only what sits above the ride. If the ride's own screen is in
    // the stack it stays mounted, with whatever the rider was doing on it.
    Route<dynamic>? kept;
    nav.popUntil((route) {
      final stop =
          route.isFirst || _rideStageRoutes.contains(route.settings.name);
      if (stop) kept = route;
      return stop;
    });
    if (kept != null && !kept!.isFirst) return true;
    await WidgetsBinding.instance.endOfFrame;
  }

  await RideRestoreCoordinator.instance.resumeIfNeeded();
  return true;
}

/// Scheduled rides never write the live-ride snapshot; their notifications
/// open the reservation instead.
bool _openReservation(String id) {
  final reservation = AppScope.instance.reservations.byId(id);
  if (reservation == null || id.startsWith('ondemand-')) return false;
  return pushPageOnce(
    () => UpcomingReservationPage(reservationId: reservation.reservationId),
    AppRoutes.reservationUpcoming,
  );
}

/// A notification row tap: one open at a time, and a short note when the
/// ride can no longer be opened instead of an inert row.
///
/// FLOW-18: an ended ride then opens where it is kept ([onEnded], the
/// Ride History page from the Notifications screen) instead of nothing.
Future<void> openNotificationRide(
  BuildContext context,
  String rideId, {
  NotificationRideOpener? open,
  VoidCallback? onEnded,
}) async {
  if (_rowTapBusy) return;
  _rowTapBusy = true;
  try {
    final opened = await (open ?? openRideFromNotification)(rideId);
    if (!opened && context.mounted) {
      MoveraToast.show(context, context.l10n.notificationRideEnded);
      onEnded?.call();
    }
  } finally {
    _rowTapBusy = false;
  }
}

String? notificationRideTarget({
  String? rideId,
  String? deepLink,
}) {
  final direct = rideId?.trim();
  if (direct?.isNotEmpty == true) return direct;

  final link = deepLink?.trim();
  if (link == null || link.isEmpty) return null;
  final uri = Uri.tryParse(link);
  if (uri == null || uri.scheme != 'movera' || uri.host != 'ride') {
    return null;
  }
  if (uri.pathSegments.length != 1) return null;
  final id = uri.pathSegments.single.trim();
  return id.isEmpty ? null : id;
}
