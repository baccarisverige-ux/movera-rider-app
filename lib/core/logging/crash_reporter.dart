import 'package:flutter/foundation.dart';
import 'package:movera_rider/core/constants/app_version.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/core/observability/observability.dart';

/// Sends crashes and reported errors to `POST /telemetry/crashes` through
/// [Observability.crashes] (contract v0.16.0 §11). No vendor, no DSN.
///
/// Owner 2026-10-29: "Add automatic and add this in term and condition":
/// automatic, no switch. [fatal] marks an uncaught error (`kind: crash`);
/// a caught error shown to the rider is `kind: error`.
class CrashReporter {
  const CrashReporter();

  void record(
    Object error,
    StackTrace stack, {
    String? rideId,
    String? screen,
    String? operation,
    String? requestId,
    bool fatal = false,
  }) {
    final extra = Observability.sanitize({
      'rideId': rideId,
      'screen': screen,
      'operation': operation,
      'requestId': requestId,
      'kind': fatal ? 'crash' : 'error',
      'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
      'appVersion': appVersion,
    });
    Observability.crashes.record(error, stack, extra: extra);
    AppLog.fatal('crash', error: error, stackTrace: stack, extra: extra);
  }
}
