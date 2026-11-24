import 'dart:async';

import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/config/api_rider_config_repository.dart';
import 'package:movera_rider/core/constants/app_version.dart';
import 'package:movera_rider/core/observability/crash_breadcrumbs.dart';
import 'package:movera_rider/core/observability/crash_catcher.dart';
import 'package:movera_rider/core/observability/crash_files.dart';
import 'package:movera_rider/core/observability/crash_report.dart';
import 'package:movera_rider/core/observability/observability.dart';

/// Owner 2026-11-24 "Add to admin all kind of crash" (contract v0.18.157
/// `contract.json#crashCatcher`): starts the crash catcher of a live build
/// (where crash reports go out): the unclean end of the last run is
/// reported, the running marker and the freeze watch start, the main
/// isolate's own errors are listened to, reports a previous run could not
/// send go again, and the zone's `crashReports.on` is followed.
Future<void> startCrashCatcher() async {
  final sink = AppScope.instance.observabilitySink;
  if (sink == null) return;
  final files = await openCrashFiles();
  final version = CrashReport.splitVersion(appVersion);
  final catcher = CrashCatcher(
    files: files ?? MemoryCrashFiles(),
    markerSupported: files != null && crashMarkerSupported,
    appVersion: version.version,
    build: version.build,
    send: (event) => Observability.crashes.record(
      event.message,
      StackTrace.fromString(event.stack),
      extra: {
        'kind': event.kind,
        'screen': ?event.screen,
        'nativeReason': ?event.nativeReason,
        'freezeMs': ?event.freezeMs,
        'breadcrumbs': ?event.breadcrumbs,
        ...event.extra,
      },
    ),
  );
  CrashCatcher.instance = catcher;
  CrashReport.context = catcher.context;
  if (files != null) sink.outbox = catcher.outbox;
  sink.resendOutbox();
  catcher.start();
  listenToIsolateErrors(
    (error, stack) => Observability.crashes.record(
      error,
      stack,
      extra: const {'kind': CrashReport.kindDartError, 'operation': 'isolate'},
    ),
  );
  final config = AppScope.instance.riderConfig;
  if (config is ApiRiderConfigRepository) {
    Future<void> follow() async {
      try {
        final current = await config.current();
        catcher.reportingOn = current.crashReportsOn;
        CrashReport.currentZoneId = config.homeZoneId;
      } catch (_) {
        // Never shown and never fatal: a crash report must not crash the app.
      }
    }

    config.addListener(() => unawaited(follow()));
    unawaited(follow());
  }
  CrashBreadcrumbs.instance.add('lifecycle', 'start');
}
