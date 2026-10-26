import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/core/observability/http_observability.dart';
import 'package:movera_rider/core/observability/observability.dart';

/// Live stability: on the staging build every AppLog line became its own
/// POST /telemetry/logs the moment it was written (25 at once when Select
/// ride opened, one per trip poll after that), against a server that does
/// not serve the path. Telemetry must never crowd out the ride's own calls.
void main() {
  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

  test('routine lines go out one at a time, errors and crashes at once',
      () async {
    final inFlight = <Completer<http.Response>>[];
    final paths = <String>[];
    final sink = HttpObservabilitySink(
      baseUrl: 'https://api.movera.example',
      client: MockClient((request) {
        paths.add(request.url.path);
        final c = Completer<http.Response>();
        inFlight.add(c);
        return c.future;
      }),
    );
    for (var i = 0; i < 5; i++) {
      sink.log(TelemetryLevel.info, 'api.GET', extra: {'i': i});
    }
    await settle();
    expect(paths, ['/api/v1/telemetry/logs'], reason: 'one in flight per path');
    sink.log(TelemetryLevel.error, 'ride.failed');
    sink.record(StateError('boom'), StackTrace.current);
    await settle();
    expect(paths, hasLength(2), reason: 'the crash path has its own lane');
    expect(paths.last, '/api/v1/telemetry/crashes');
    inFlight[0].complete(http.Response('', 202));
    await settle();
    expect(paths, hasLength(3));
    for (final c in inFlight) {
      if (!c.isCompleted) c.complete(http.Response('', 202));
    }
    await settle();
    sink.dispose();
  });

  test('a path the server does not serve (404) is left alone for a while',
      () async {
    var now = DateTime(2026, 10, 26, 9);
    var calls = 0;
    final sink = HttpObservabilitySink(
      baseUrl: 'https://api.movera.example',
      clock: () => now,
      client: MockClient((_) async {
        calls++;
        return http.Response('{"code":"not_found"}', 404);
      }),
    );
    sink.log(TelemetryLevel.info, 'a');
    await settle();
    expect(calls, 1);
    for (var i = 0; i < 10; i++) {
      sink.log(TelemetryLevel.warning, 'b$i');
    }
    await settle();
    expect(calls, 1, reason: 'muted after the 404');
    now = now.add(const Duration(minutes: 11));
    sink.log(TelemetryLevel.info, 'c');
    await settle();
    expect(calls, 2, reason: 'tried again after the quiet period');
    sink.dispose();
  });

  test('debug and info lines are capped per minute; the count rides along',
      () async {
    var now = DateTime(2026, 10, 26, 9);
    final bodies = <Map<String, dynamic>>[];
    final sink = HttpObservabilitySink(
      baseUrl: 'https://api.movera.example',
      routineLinesPerMinute: 3,
      clock: () => now,
      client: MockClient((request) async {
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response('', 202);
      }),
    );
    for (var i = 0; i < 10; i++) {
      sink.log(TelemetryLevel.info, 'poll', extra: {'i': i});
      await settle();
    }
    expect(bodies, hasLength(3));
    sink.log(TelemetryLevel.warning, 'realtime.poll_failed');
    await settle();
    expect(bodies, hasLength(4), reason: 'a warning is never dropped');
    expect(bodies.last['droppedLines'], 7);
    now = now.add(const Duration(minutes: 1, seconds: 1));
    sink.log(TelemetryLevel.info, 'poll');
    await settle();
    expect(bodies, hasLength(5), reason: 'a new minute, a new budget');
    expect(bodies.last.containsKey('droppedLines'), isFalse);
    sink.dispose();
  });

  test('the queue is bounded: a burst of 100 lines never means 100 requests',
      () async {
    var calls = 0;
    final sink = HttpObservabilitySink(
      baseUrl: 'https://api.movera.example',
      queueLimit: 5,
      routineLinesPerMinute: 1000,
      client: MockClient((_) async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 1));
        return http.Response('', 202);
      }),
    );
    for (var i = 0; i < 100; i++) {
      sink.log(TelemetryLevel.info, 'line $i');
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(calls, lessThanOrEqualTo(6));
    expect(sink.droppedCount, greaterThan(90));
    sink.dispose();
  });
}
