import 'package:flutter/foundation.dart';
import 'package:movera_rider/core/constants/app_version.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/core/observability/observability.dart';

/// Sentry/Crashlytics adapter. No DSN is stored in the app.
class CrashReporter {
  const CrashReporter();

  void record(
    Object error,
    StackTrace stack, {
    String? rideId,
    String? screen,
    String? operation,
    String? requestId,
  }) {
    final extra = Observability.sanitize({
      'rideId': rideId,
      'screen': screen,
      'operation': operation,
      'requestId': requestId,
      'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
      'appVersion': appVersion,
    });
    Observability.crashes.record(error, stack, extra: extra);
    AppLog.fatal('crash', error: error, stackTrace: stack, extra: extra);
  }
}
