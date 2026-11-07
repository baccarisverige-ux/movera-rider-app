import 'package:flutter/widgets.dart';
import 'package:movera_rider/app/router/routes.dart';

/// Owner 2026-11-07 "Passager : retours en arrière": Finding, Waiting, the
/// live trip and the receipt are pushed over Home, so the restore
/// coordinator's `showing` stays `home` while they are on screen. This
/// observer knows whether such a ride screen is in the navigator, so the
/// Home-only "open the server's active trip" never pops a ride the rider is
/// looking at back to the first route and rebuilds it.
class RideStageRouteObserver extends NavigatorObserver {
  /// The pushed routes that show a ride.
  static const rideRoutes = {
    AppRoutes.findingDriver,
    AppRoutes.waitingForDriver,
    AppRoutes.rideCompleted,
    AppRoutes.reservationLive,
  };

  static final Set<Route<dynamic>> _onStack = {};

  /// True while a ride screen (search, trip or receipt) is in the stack.
  static bool get rideOnScreen {
    _onStack.removeWhere((route) {
      try {
        return !route.isActive;
      } catch (_) {
        return true;
      }
    });
    return _onStack.isNotEmpty;
  }

  static void _add(Route<dynamic>? route) {
    if (route != null && rideRoutes.contains(route.settings.name)) {
      _onStack.add(route);
    }
  }

  static void _drop(Route<dynamic>? route) {
    if (route != null) _onStack.remove(route);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _add(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _drop(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _drop(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _drop(oldRoute);
    _add(newRoute);
  }
}
