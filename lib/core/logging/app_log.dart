import 'package:flutter/foundation.dart';
import 'package:movera_rider/core/observability/crash_breadcrumbs.dart';
import 'package:movera_rider/core/observability/observability.dart';

enum LogLevel { debug, info, warning, error, fatal }

abstract final class AppLog {
  static void debug(String event, {Map<String, Object?> extra = const {}}) {
    _write(LogLevel.debug, event, extra: extra);
  }

  static void info(String event, {Map<String, Object?> extra = const {}}) {
    _write(LogLevel.info, event, extra: extra);
  }

  static void warning(String event, {Map<String, Object?> extra = const {}}) {
    _write(LogLevel.warning, event, extra: extra);
  }

  static void error(
    String event, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> extra = const {},
  }) {
    _write(
      LogLevel.error,
      event,
      extra: extra,
      error: error,
      stackTrace: stackTrace,
    );
  }

  static void fatal(
    String event, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> extra = const {},
  }) {
    _write(
      LogLevel.fatal,
      event,
      extra: extra,
      error: error,
      stackTrace: stackTrace,
    );
  }

  static void _write(
    LogLevel level,
    String event, {
    Map<String, Object?> extra = const {},
    Object? error,
    StackTrace? stackTrace,
  }) {
    final safe = Observability.sanitize(extra);
    _breadcrumb(level, event, safe);
    Observability.logger.log(
      TelemetryLevel.values.byName(level.name),
      event,
      extra: safe,
      error: error,
      stackTrace: stackTrace,
    );
    // Production delivery happens through LoggerSink. Console output remains a
    // developer-only surface so riders never see internal diagnostics.
    if (!kDebugMode) return;
    debugPrint('[movera:${level.name}] $event $safe');
    if (error != null) debugPrint('  error=$error');
    if (stackTrace != null) debugPrint('$stackTrace');
  }

  /// v0.18.157 (`contract.json#crashCatcher.breadcrumbs`): a failed API call
  /// is a `network` breadcrumb (method, path without ids, status), any other
  /// warning or error line a `log` one (its event name only).
  static void _breadcrumb(
    LogLevel level,
    String event,
    Map<String, Object?> extra,
  ) {
    try {
      final status = extra['status'];
      if (event.startsWith('api.') && extra['path'] is String) {
        if (event == 'api.timeout') {
          CrashBreadcrumbs.instance.network(
            'call',
            extra['path']! as String,
            null,
          );
        } else if (status is int && status >= 400) {
          CrashBreadcrumbs.instance.network(
            event.substring(4),
            extra['path']! as String,
            status,
          );
        }
        return;
      }
      if (level.index >= LogLevel.warning.index && event != 'crash') {
        CrashBreadcrumbs.instance.add('log', '${level.name} $event');
      }
    } catch (_) {
      // Never shown and never fatal: a crash report must not crash the app.
    }
  }
}
