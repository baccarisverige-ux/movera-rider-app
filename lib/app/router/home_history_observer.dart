import 'package:flutter/widgets.dart';
import 'package:movera_rider/core/observability/crash_report.dart';
import 'package:movera_rider/core/web/web_overlay.dart';
import 'package:movera_rider/features/ride_booking/application/ride_restore_coordinator.dart';

/// Monotonic signal for route-stack changes.
final ValueNotifier<int> moveraNavigationEpoch = ValueNotifier<int>(0);

/// Keep Chrome from treating Home sheet overscroll as history.back.
class HomeHistoryObserver extends NavigatorObserver {
  void _sync({bool unlockFirst = false}) {
    if (unlockFirst) setWebHomeLock(false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final nav = navigator;
      final atRoot = nav == null || !nav.canPop();
      final home =
          RideRestoreCoordinator.instance.showing == RestoredSurface.home;
      setWebHomeLock(atRoot && home);
    });
  }

  void _routeChanged({bool unlockFirst = false, Route<dynamic>? top}) {
    moveraNavigationEpoch.value += 1;
    // Contract v0.16.0: a crash report says which screen was on top.
    if (top != null) CrashReport.currentScreen = top.settings.name;
    _sync(unlockFirst: unlockFirst);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routeChanged(unlockFirst: true, top: route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _routeChanged(top: previousRoute);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _routeChanged();

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _routeChanged(top: newRoute);
}
