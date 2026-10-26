import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/analytics/analytics.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/core/logging/crash_reporter.dart';
import 'package:movera_rider/core/observability/observability.dart';

class _Logger implements LoggerSink {
  final events = <String>[];
  Map<String, Object?>? lastExtra;

  @override
  void log(
    TelemetryLevel level,
    String event, {
    Map<String, Object?> extra = const {},
    Object? error,
    StackTrace? stackTrace,
  }) {
    events.add(event);
    lastExtra = extra;
  }
}

class _Analytics implements AnalyticsSink {
  final events = <String>[];
  Map<String, Object?>? lastExtra;

  @override
  void track(String event, {Map<String, Object?> extra = const {}}) {
    events.add(event);
    lastExtra = extra;
  }
}

class _Crashes implements CrashSink {
  int count = 0;
  Map<String, Object?>? lastExtra;

  @override
  void record(
    Object error,
    StackTrace stackTrace, {
    Map<String, Object?> extra = const {},
  }) {
    count += 1;
    lastExtra = extra;
  }
}

void main() {
  tearDown(Observability.reset);

  test(
    'analytics and logs reach configured sinks with sensitive fields removed',
    () {
      final logger = _Logger();
      final analytics = _Analytics();
      Observability.configure(loggerSink: logger, analyticsSink: analytics);

      Analytics.track(
        'booking_submitted',
        extra: const {'rideId': 'r1', 'token': 'secret', 'phone': '+46000'},
      );

      expect(analytics.events, ['booking_submitted']);
      expect(analytics.lastExtra, {'rideId': 'r1'});
      expect(logger.events, contains('analytics.booking_submitted'));
      expect(logger.lastExtra, {'rideId': 'r1'});
    },
  );

  test('CrashReporter reaches CrashSink independently of debug console', () {
    final crashes = _Crashes();
    Observability.configure(crashSink: crashes);

    const CrashReporter().record(
      StateError('boom'),
      StackTrace.empty,
      rideId: 'r1',
      operation: 'restore',
    );

    expect(crashes.count, 1);
    expect(crashes.lastExtra?['rideId'], 'r1');
  });

  test('AppLog always forwards to LoggerSink', () {
    final logger = _Logger();
    Observability.configure(loggerSink: logger);

    AppLog.warning(
      'test.event',
      extra: const {'password': 'no', 'rideId': 'r1'},
    );

    expect(logger.events, ['test.event']);
    expect(logger.lastExtra, {'rideId': 'r1'});
  });
}
