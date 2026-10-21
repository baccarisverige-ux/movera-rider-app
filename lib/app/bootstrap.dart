import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:movera_rider/app/app.dart';
import 'package:movera_rider/app/bundled_fonts.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/router/routes.dart';
import 'package:movera_rider/core/config/rider_zones.dart';
import 'package:movera_rider/core/config/trip_zone_config.dart';
import 'package:movera_rider/core/debug/movera_qa.dart';
import 'package:movera_rider/features/home/application/home_controller.dart';
import 'package:movera_rider/core/debug/web_qa_hooks.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/core/maps/native_maps_config.dart';
import 'package:movera_rider/core/web/web_ride_pagehide.dart';
import 'package:movera_rider/core/web/web_splash.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/notifications/application/notification_navigation.dart';
import 'package:movera_rider/features/notifications/application/push_coordinator.dart';
import 'package:movera_rider/features/notifications/presentation/notifications.dart';
import 'package:movera_rider/features/ride_booking/application/ride_restore_coordinator.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/features/wallet/data/wallet_repository.dart';
import 'package:movera_rider/features/ride_booking/data/web_ride_seed.dart';
import 'package:movera_rider/features/safety/application/ride_check_controller.dart';
import 'package:movera_rider/features/safety/presentation/safety_hub.dart';


PushCoordinator? _pushCoordinator;

Future<void> _registerExistingPushSession() async {
  if (AppScope.instance.environment.allowsMockTransport) return;
  final access = await AppScope.instance.tokens.readAccess();
  final refresh = await AppScope.instance.tokens.readRefresh();
  if (access?.isNotEmpty != true || refresh?.isNotEmpty != true) return;
  try {
    // Only a rider who accepted the in-app explanation; no cold OS prompt.
    await AppScope.instance.pushPermission.registerIfConsented(
      logEvent: 'push.session_restore_deferred',
    );
  } catch (error) {
    AppLog.warning(
      'push.session_restore_deferred',
      extra: {'error': error.toString()},
    );
  }
}

void _openNotificationsFromPush() {
  unawaited(() async {
    // Nothing opens over Sign in, and a second open does not stack a copy.
    if (await navigationBlockedBySignIn()) return;
    pushPageOnce(() => const NotificationScreen(), AppRoutes.notifications);
  }());
}

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  // UI-15: bundled Poppins, when present, means no font download at start.
  await configureBundledFonts();
  // Before anything can call the API: a 401 during start-up still has a
  // Sign in screen to show.
  registerSessionExpiredNavigation();
  // Before the first map builds: an iOS build without a Maps key must show
  // the no-map fallback instead of crashing inside the Maps SDK.
  await NativeMapsConfig.load();
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  installWebRidePagehide(RideRestoreCoordinator.instance.onPageHide);
  // Public web gets one navigation-only bridge for Safety. It exposes no
  // ride seeding, matching controls, or Safety mutations.
  installSafetyNavigationBridge(
    () => pushPageOnce(() => const SafetyHub(), AppRoutes.safety),
  );

  // Debug / MOVERA_QA keeps the broader mutation-capable QA hooks gated off
  // from public release builds.
  if (moveraQaHooksEnabled) {
    registerWebQaHooks();
    installRideCheckQaHook();
  }
  AppScope.instance.maps.onOwnerDebug = reportMapOwner;
  // Ride check (RC1): the trip screen checks live positions against the
  // admin's triggers. On in the app; widget tests turn it on themselves.
  RideCheckController.tripMonitoring = true;

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    // CODE-20: record() already logs it as a fatal `crash`; logging it a
    // second time counted every framework error twice.
    AppScope.instance.crashes.record(
      details.exception,
      details.stack ?? StackTrace.empty,
      screen: details.library,
    );
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    AppLog.fatal('platform.error', error: error, stackTrace: stack);
    return true;
  };

  AppScope.instance.lifecycle.attach();
  if (AppEnv.current.flavor == AppFlavor.demo) {
    await WalletStore.seedDemoBalance();
  }
  await AppScope.instance.reservations.hydrate();
  await AppScope.instance.profile.hydrateLocalThenServer();
  // Q48: the saved language, else the default of the rider's zone; a
  // later good fix in another zone moves the default with it.
  await AppScope.instance.language.load(
    config: AppScope.instance.riderConfig,
    zone: await currentRiderZone(),
  );
  HomeLocationController.onGoodFix = (point) => unawaited(
    AppScope.instance.language.useZone(
      config: AppScope.instance.riderConfig,
      zone: RiderZones.at(point.latitude, point.longitude),
    ),
  );
  // Ride categories from the server. Not awaited: the built-in list stands
  // in until the answer lands, and Select Ride asks again when it opens.
  unawaited(AppScope.instance.catalog.load());
  // Scheduled-ride rules (cancel window, fee); defaults until they land.
  unawaited(AppScope.instance.reservations.refreshRules());
  await _registerExistingPushSession();
  unawaited(FindingDriverController.flushPendingCancels());
  AppLog.info('app.start', extra: {'platform': kIsWeb ? 'web' : 'native'});

  runZonedGuarded(
    () {
      runApp(const MoveraApp());
      _pushCoordinator ??= PushCoordinator(
        push: AppScope.instance.push,
        openRide: openRideFromNotification,
        openNotifications: _openNotificationsFromPush,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // The HTML boot screen covers the blank page while the bundle loads.
        // Clear it once there is a real frame behind it, and before anything
        // slower runs, so the rider is not kept waiting on push registration.
        dismissWebSplash();
        unawaited(_pushCoordinator!.start());
      });
    },
    (error, stack) {
      AppScope.instance.crashes.record(error, stack);
      AppLog.fatal('zone.error', error: error, stackTrace: stack);
    },
  );
}
