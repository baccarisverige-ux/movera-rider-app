import 'package:flutter/widgets.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/core/web/rider_map_bridge.dart';
import 'package:movera_rider/core/web/web_gpu.dart';
import 'package:movera_rider/features/ride_booking/application/ride_restore_coordinator.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';

class AppLifecycleObserver with WidgetsBindingObserver {
  void attach() => WidgetsBinding.instance.addObserver(this);

  void detach() => WidgetsBinding.instance.removeObserver(this);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // On the web: how many Google maps the page holds and whether the
    // browser has taken WebGL contexts away, next to every foreground /
    // background change, so a blank screen or a reload on the phone can be
    // read against them (docs/web-lifecycle-investigation.md).
    final maps = RiderMapBridge.stats();
    final gpu = webGlContextEvents();
    AppLog.info(
      'app.lifecycle',
      extra: {
        'state': state.name,
        if (maps != null) 'liveMaps': maps.live,
        if (maps != null) 'createdMaps': maps.created,
        if (maps != null) 'recycledMaps': maps.recycled,
        if (gpu.lost > 0) 'webglLost': gpu.lost,
        if (gpu.restored > 0) 'webglRestored': gpu.restored,
      },
    );
    switch (state) {
      case AppLifecycleState.resumed:
        RideSnapshotStore.read().then((snapshot) {
          AppLog.info(
            'app.resume.refresh',
            extra: {'ride': snapshot?.status.name ?? 'none'},
          );
        });
        RideRestoreCoordinator.instance.resumeIfNeeded();
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        RideSnapshotStore.touchCurrent().catchError((Object error) {
          AppLog.error(
            'app.lifecycle.persist_failed',
            extra: {'reason': error.toString()},
          );
        });
    }
  }
}