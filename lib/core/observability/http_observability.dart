import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:movera_rider/core/observability/crash_report.dart';
import 'package:movera_rider/core/observability/observability.dart';

/// Privacy-safe remote observability sink. It intentionally uses raw HTTP
/// instead of ApiClient so logging an ApiClient request cannot recurse.
///
/// Telemetry is fire-and-forget (contract: `POST /telemetry/*`, one entry
/// per request) and must never get in the way of the ride: the browser
/// allows a handful of connections per host, and the live server is small.
/// So each path sends one request at a time from a bounded queue, routine
/// lines (debug, info) are capped per minute, and a path the server does
/// not serve (404) is left alone for a while instead of being hit on every
/// log line. Errors, crashes and warnings always go out.
class HttpObservabilitySink implements LoggerSink, AnalyticsSink, CrashSink {
  HttpObservabilitySink({
    required this.baseUrl,
    http.Client? client,
    this.routineLinesPerMinute = 20,
    this.queueLimit = 40,
    this.muteAfterNotFound = const Duration(minutes: 10),
    this.app = 'rider',
    this.appVersion,
    this.build,
    this.platform,
    this.accessToken,
    this.burstWindow = const Duration(minutes: 1),
    this.retryDelay = const Duration(seconds: 30),
    this.maxRetryDelay = const Duration(minutes: 10),
    this.maxAttempts = 6,
    DateTime Function()? clock,
  }) : _client = client ?? http.Client(),
       _clock = clock ?? DateTime.now;

  /// Contract v0.16.0 crash report fields (`contract.json#telemetry.crashReport`).
  final String app;
  final String? appVersion;
  final String? build;
  final String? platform;

  /// The signed-in rider's access token, sent like every other call; null
  /// when signed out. A failure to read it never stops the report.
  final Future<String?> Function()? accessToken;

  /// The same crash again within this window is counted, not sent again.
  final Duration burstWindow;

  /// Crash reports that could not be delivered (offline, 5xx, 429) are kept
  /// and tried again after [retryDelay], doubling up to [maxRetryDelay], at
  /// most [maxAttempts] times.
  final Duration retryDelay;
  final Duration maxRetryDelay;
  final int maxAttempts;

  final Map<String, DateTime> _recentCrashes = {};

  /// Crash reports not sent because the same one was just sent.
  int get repeatedCount => _repeated;
  int _repeated = 0;

  final String baseUrl;
  final http.Client _client;
  final DateTime Function() _clock;

  /// How many debug/info lines a minute may leave the device. The rest are
  /// counted and the count rides along on the next line that is sent.
  final int routineLinesPerMinute;

  /// Entries waiting per path; the oldest routine ones are dropped first.
  final int queueLimit;

  /// How long a path answered with 404 (not enabled on this server) is
  /// left alone.
  final Duration muteAfterNotFound;

  final Map<String, _PathQueue> _queues = {};
  final Queue<DateTime> _routineSent = Queue<DateTime>();
  int _routineDropped = 0;
  bool _disposed = false;

  /// Requests sent so far (tests and diagnostics).
  int get sentCount => _sent;
  int _sent = 0;

  /// Lines not sent because of the per-minute cap or a full queue.
  int get droppedCount => _droppedTotal;
  int _droppedTotal = 0;

  void _drop() {
    _routineDropped += 1;
    _droppedTotal += 1;
  }

  void _post(
    String path,
    Map<String, Object?> body, {
    required bool routine,
    bool retry = false,
  }) {
    if (_disposed) return;
    final queue = _queues.putIfAbsent(path, () => _PathQueue());
    final now = _clock();
    if (queue.mutedUntil != null) {
      if (now.isBefore(queue.mutedUntil!)) return;
      queue.mutedUntil = null;
    }
    if (routine && !_routineAllowed(now)) {
      _drop();
      return;
    }
    if (_routineDropped > 0 && !retry) {
      body = {...body, 'droppedLines': _routineDropped};
      _routineDropped = 0;
    }
    queue.pending.add(_Entry(body, routine: routine, retry: retry));
    while (queue.pending.length > queueLimit) {
      final index = queue.pending.indexWhere((e) => e.routine);
      queue.pending.removeAt(index == -1 ? 0 : index);
      _drop();
    }
    _drain(path, queue);
  }

  bool _routineAllowed(DateTime now) {
    final minuteAgo = now.subtract(const Duration(minutes: 1));
    while (_routineSent.isNotEmpty && _routineSent.first.isBefore(minuteAgo)) {
      _routineSent.removeFirst();
    }
    if (_routineSent.length >= routineLinesPerMinute) return false;
    _routineSent.addLast(now);
    return true;
  }

  void _drain(String path, _PathQueue queue) {
    if (queue.inFlight || queue.pending.isEmpty || _disposed) return;
    if (queue.retryTimer != null) return;
    final entry = queue.pending.removeAt(0);
    queue.inFlight = true;
    _sent += 1;
    var failed = false;
    unawaited(
      _send(path, entry)
          .then((response) {
            if (response.statusCode == 404) {
              // Not enabled on this server: nothing more to send for now.
              queue.mutedUntil = _clock().add(muteAfterNotFound);
              queue.pending.clear();
            } else if (response.statusCode >= 500 ||
                response.statusCode == 429) {
              failed = true;
            }
          })
          .catchError((_) {
            failed = true;
          })
          .whenComplete(() {
            queue.inFlight = false;
            if (failed && entry.retry && !_disposed) {
              _retryLater(path, queue, entry);
              return;
            }
            if (!failed) queue.failures = 0;
            _drain(path, queue);
          }),
    );
  }

  Future<http.Response> _send(String path, _Entry entry) async {
    String? token;
    if (accessToken != null) {
      try {
        token = await accessToken!();
      } catch (_) {
        token = null;
      }
    }
    return _client
        .post(
          Uri.parse('$baseUrl$path'),
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            if (token != null && token.isNotEmpty)
              'Authorization': 'Bearer $token',
          },
          body: jsonEncode(entry.body),
        )
        .timeout(const Duration(seconds: 10));
  }

  /// Offline or the server is busy: keep the report (at the front, so the
  /// order holds) and try again later instead of losing it.
  void _retryLater(String path, _PathQueue queue, _Entry entry) {
    entry.attempts += 1;
    if (entry.attempts >= maxAttempts) {
      _droppedTotal += 1;
      _drain(path, queue);
      return;
    }
    queue.pending.insert(0, entry);
    while (queue.pending.length > queueLimit) {
      queue.pending.removeLast();
      _droppedTotal += 1;
    }
    queue.failures += 1;
    var delay = retryDelay * (1 << (queue.failures - 1).clamp(0, 16));
    if (delay > maxRetryDelay) delay = maxRetryDelay;
    queue.retryTimer = Timer(delay, () {
      queue.retryTimer = null;
      _drain(path, queue);
    });
  }

  @override
  void log(
    TelemetryLevel level,
    String event, {
    Map<String, Object?> extra = const {},
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (_isAnsweredApiCall(level, event, extra)) return;
    _post('/api/v1/telemetry/logs', {
      'level': level.name,
      'event': event,
      'extra': Observability.sanitize(extra),
      if (error != null) 'error': Observability.scrubText(error.toString()),
    }, routine: level == TelemetryLevel.debug || level == TelemetryLevel.info);
  }

  /// Audit Phase 7: every API call was also sent as a telemetry line, so the
  /// trip screens' 2 s ride poll cost a second request each time (measured
  /// live: 18 telemetry posts a minute next to 30 polls) and used up the
  /// routine cap meant for real events. The server already logs each request
  /// with its requestId; only failed calls (status 400 and up, timeouts) go
  /// out from here.
  static bool _isAnsweredApiCall(
    TelemetryLevel level,
    String event,
    Map<String, Object?> extra,
  ) {
    if (level != TelemetryLevel.debug && level != TelemetryLevel.info) {
      return false;
    }
    if (!event.startsWith('api.')) return false;
    final status = extra['status'];
    return status is int && status < 400;
  }

  @override
  void track(String event, {Map<String, Object?> extra = const {}}) {
    _post('/api/v1/telemetry/analytics', {
      'event': event,
      'extra': Observability.sanitize(extra),
    }, routine: true);
  }

  /// Contract v0.16.0: a crash (uncaught) or an error (caught and shown),
  /// with the app, platform, version, build, screen and time. `extra` may
  /// carry `screen` and `kind`; they go into the report's own fields.
  @override
  void record(
    Object error,
    StackTrace stackTrace, {
    Map<String, Object?> extra = const {},
  }) {
    if (_disposed) return;
    try {
      final now = _clock();
      final kind = extra['kind'] == CrashReport.kindError
          ? CrashReport.kindError
          : CrashReport.kindCrash;
      final screen = extra['screen'] is String
          ? extra['screen'] as String
          : CrashReport.currentScreen;
      final body = CrashReport.body(
        error: error,
        stackTrace: stackTrace,
        extra: extra,
        app: app,
        platform: platform,
        appVersion: appVersion,
        build: build,
        screen: screen,
        kind: kind,
        occurredAt: now,
      );
      final key = CrashReport.fingerprint(
        kind,
        body['error']! as String,
        body['stack']! as String,
      );
      _recentCrashes.removeWhere((_, at) => now.difference(at) >= burstWindow);
      if (_recentCrashes.containsKey(key)) {
        _repeated += 1;
        return;
      }
      if (_recentCrashes.length >= 100) _recentCrashes.clear();
      _recentCrashes[key] = now;
      _post('/api/v1/telemetry/crashes', body, routine: false, retry: true);
    } catch (_) {
      // A crash report must never crash the app.
    }
  }

  void dispose() {
    _disposed = true;
    for (final queue in _queues.values) {
      queue.retryTimer?.cancel();
    }
    _queues.clear();
    _client.close();
  }
}

class _PathQueue {
  final List<_Entry> pending = <_Entry>[];
  bool inFlight = false;
  DateTime? mutedUntil;
  Timer? retryTimer;
  int failures = 0;
}

class _Entry {
  _Entry(this.body, {required this.routine, this.retry = false});
  final Map<String, Object?> body;
  final bool routine;
  final bool retry;
  int attempts = 0;
}
