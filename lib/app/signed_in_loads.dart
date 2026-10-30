import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/config/api_rider_config_repository.dart';
import 'package:movera_rider/core/config/trip_zone_config.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';

/// Contract v0.18.2 `auth.beforeSignIn` (owner 2026-10-30, "Yes, stop it
/// (Recommended)"): the reads that need the rider's bearer token (config,
/// its stream, zones, content, ride categories, scheduled-ride rules,
/// pending cancels) start at launch only when a session is stored, and
/// otherwise right after sign-in. Before that the app uses its built-in
/// defaults (or what it kept from an earlier session).
class SignedInLoads {
  SignedInLoads({
    required this.needsSession,
    required this.hasSession,
    required this.load,
  });

  /// False where the app has no sign-in (demo and test builds on the mock).
  final bool Function() needsSession;

  /// Whether this device holds an access and a refresh token.
  final Future<bool> Function() hasSession;

  /// Starts the reads.
  final Future<void> Function() load;

  /// At launch: the reads start only with a stored session (or in a build
  /// without sign-in). True when they started.
  Future<bool> atLaunch() async {
    if (needsSession()) {
      bool signedIn;
      try {
        signedIn = await hasSession();
      } catch (_) {
        signedIn = false;
      }
      if (!signedIn) return false;
    }
    await load();
    return true;
  }

  /// Right after sign-in.
  Future<void> afterSignIn() => load();

  static SignedInLoads? _app;

  /// The app's own, wired to [AppScope].
  static SignedInLoads get app => _app ??= SignedInLoads(
    needsSession: () => !AppScope.instance.environment.allowsMockTransport,
    hasSession: () async {
      final tokens = AppScope.instance.tokens;
      final access = await tokens.readAccess();
      final refresh = await tokens.readRefresh();
      return access?.isNotEmpty == true && refresh?.isNotEmpty == true;
    },
    load: startServerReads,
  );

  @visibleForTesting
  static set debugApp(SignedInLoads? value) => _app = value;
}

/// The reads that need a session. Each is safe to start again: a second
/// start reads again (zones, content, catalog, rules) or keeps the watch it
/// already has (config stream).
Future<void> startServerReads() async {
  unawaited(AppScope.instance.zones.refresh());
  // Owner 2026-10-27: new rider settings reach an open app at once
  // (config_published on /rider/config/stream) and are read again on start;
  // the car types follow the published catalog.
  final config = AppScope.instance.riderConfig;
  if (config is ApiRiderConfigRepository) {
    final zone = await currentRiderZone();
    config.homeZoneId = zone.id;
    unawaited(AppScope.instance.content.start(zone.id));
    unawaited(config.watch(zone.id));
  }
  // Ride categories from the server. Not awaited: the built-in list stands
  // in until the answer lands, and Select Ride asks again when it opens.
  unawaited(AppScope.instance.catalog.load());
  // Scheduled-ride rules (cancel window, fee); defaults until they land.
  unawaited(AppScope.instance.reservations.refreshRules());
  unawaited(FindingDriverController.flushPendingCancels());
}
