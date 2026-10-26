import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:http/http.dart' as http;
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
    DateTime Function()? clock,
  }) : _client = client ?? http.Client(),
       _clock = clock ?? DateTime.now;

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

  void _post(String path, Map<String, Object?> body, {required bool routine}) {
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
    if (_routineDropped > 0) {
      body = {...body, 'droppedLines': _routineDropped};
      _routineDropped = 0;
    }
    queue.pending.add(_Entry(body, routine: routine));
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
    final entry = queue.pending.removeAt(0);
    queue.inFlight = true;
    _sent += 1;
    unawaited(
      _client
          .post(
            Uri.parse('$baseUrl$path'),
            headers: const {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(entry.body),
          )
          .timeout(const Duration(seconds: 10))
          .then((response) {
            if (response.statusCode == 404) {
              // Not enabled on this server: nothing more to send for now.
              queue.mutedUntil = _clock().add(muteAfterNotFound);
              queue.pending.clear();
            }
          })
          .catchError((_) {})
          .whenComplete(() {
            queue.inFlight = false;
            _drain(path, queue);
          }),
    );
  }

  @override
  void log(
    TelemetryLevel level,
    String event, {
    Map<String, Object?> extra = const {},
    Object? error,
    StackTrace? stackTrace,
  }) {
    _post('/api/v1/telemetry/logs', {
      'level': level.name,
      'event': event,
      'extra': Observability.sanitize(extra),
      if (error != null) 'error': Observability.scrubText(error.toString()),
    }, routine: level == TelemetryLevel.debug || level == TelemetryLevel.info);
  }

  @override
  void track(String event, {Map<String, Object?> extra = const {}}) {
    _post('/api/v1/telemetry/analytics', {
      'event': event,
      'extra': Observability.sanitize(extra),
    }, routine: true);
  }

  @override
  void record(
    Object error,
    StackTrace stackTrace, {
    Map<String, Object?> extra = const {},
  }) {
    _post('/api/v1/telemetry/crashes', {
      'error': Observability.scrubText(error.toString()),
      'stack': Observability.scrubText(stackTrace.toString()),
      'extra': Observability.sanitize(extra),
    }, routine: false);
  }

  void dispose() {
    _disposed = true;
    _queues.clear();
    _client.close();
  }
}

class _PathQueue {
  final List<_Entry> pending = <_Entry>[];
  bool inFlight = false;
  DateTime? mutedUntil;
}

class _Entry {
  _Entry(this.body, {required this.routine});
  final Map<String, Object?> body;
  final bool routine;
}
