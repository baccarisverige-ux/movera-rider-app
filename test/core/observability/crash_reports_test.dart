import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/core/logging/crash_reporter.dart';
import 'package:movera_rider/core/observability/crash_report.dart';
import 'package:movera_rider/core/observability/http_observability.dart';
import 'package:movera_rider/core/observability/observability.dart';

/// Contract v0.16.0 §11 (owner 2026-10-29: "Add automatic and add this in
/// term and condition"): the rider app sends crashes and reported errors to
/// POST /telemetry/crashes on its own, scrubbed, with app, platform,
/// version, build, screen, kind and time.
void main() {
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 20));

  HttpObservabilitySink sinkWith(
    Future<http.Response> Function(http.Request) handler, {
    Future<String?> Function()? token,
    DateTime Function()? clock,
    Duration retryDelay = const Duration(milliseconds: 30),
  }) => HttpObservabilitySink(
    baseUrl: 'https://api.movera.example',
    client: MockClient(handler),
    app: 'rider',
    appVersion: '1.4.2',
    build: '17',
    platform: 'android',
    accessToken: token,
    clock: clock,
    retryDelay: retryDelay,
  );

  tearDown(() => CrashReport.currentScreen = null);

  test('a crash carries the v0.16.0 fields and the rider token', () async {
    final sent = <http.Request>[];
    final sink = sinkWith((r) async {
      sent.add(r);
      return http.Response('', 202);
    }, token: () async => 'access-1');
    CrashReport.currentScreen = '/finding-driver';
    sink.record(
      StateError('failed for anna@example.com at 59.334591, 18.063240'),
      StackTrace.current,
      extra: {'riderPhone': '+46701234567', 'rideId': 'r1'},
    );
    await settle();
    expect(sent, hasLength(1));
    expect(sent.single.url.path, '/api/v1/telemetry/crashes');
    expect(sent.single.headers['Authorization'], 'Bearer access-1');
    final body = jsonDecode(sent.single.body) as Map<String, dynamic>;
    expect(body['app'], 'rider');
    expect(body['platform'], 'android');
    expect(body['appVersion'], '1.4.2');
    expect(body['build'], '17');
    expect(body['screen'], '/finding-driver');
    expect(body['kind'], 'crash');
    expect(DateTime.parse(body['occurredAt'] as String).isUtc, isTrue);
    expect(body['error'], isNot(contains('anna@example.com')));
    expect(body['error'], isNot(contains('59.334591')));
    expect((body['extra'] as Map).containsKey('riderPhone'), isFalse);
    sink.dispose();
  });

  test('a caught error is kind error and names its own screen', () async {
    final bodies = <Map<String, dynamic>>[];
    final sink = sinkWith((r) async {
      bodies.add(jsonDecode(r.body) as Map<String, dynamic>);
      return http.Response('', 202);
    });
    sink.record(
      Exception('x'),
      StackTrace.empty,
      extra: {'kind': 'error', 'screen': 'wallet/123456'},
    );
    await settle();
    expect(bodies.single['kind'], 'error');
    expect(bodies.single['screen'], 'wallet/:id');
    expect(bodies.single.containsKey('Authorization'), isFalse);
    expect((bodies.single['extra'] as Map).containsKey('kind'), isFalse);
    sink.dispose();
  });

  test(
    'signed out: no Authorization header, a token error is ignored',
    () async {
      final sent = <http.Request>[];
      final sink = sinkWith((r) async {
        sent.add(r);
        return http.Response('', 202);
      }, token: () async => throw StateError('keystore'));
      sink.record(StateError('a'), StackTrace.empty);
      await settle();
      expect(sent.single.headers.containsKey('Authorization'), isFalse);
      sink.dispose();
    },
  );

  test('a burst of the same crash is sent once', () async {
    var now = DateTime.utc(2026, 10, 29, 9);
    var calls = 0;
    final sink = sinkWith((r) async {
      calls += 1;
      return http.Response('', 202);
    }, clock: () => now);
    final stack = StackTrace.current;
    for (var i = 0; i < 25; i++) {
      sink.record(StateError('same'), stack);
    }
    sink.record(StateError('other'), stack);
    await settle();
    expect(calls, 2);
    expect(sink.repeatedCount, 24);
    now = now.add(const Duration(minutes: 2));
    sink.record(StateError('same'), stack);
    await settle();
    expect(calls, 3, reason: 'after the window it is sent again');
    sink.dispose();
  });

  test(
    'offline: the report is kept and sent when the network is back',
    () async {
      var online = false;
      final delivered = <String>[];
      final sink = sinkWith((r) async {
        if (!online) throw http.ClientException('offline');
        delivered.add((jsonDecode(r.body) as Map)['error'] as String);
        return http.Response('', 202);
      });
      sink.record(StateError('one'), StackTrace.empty);
      sink.record(StateError('two'), StackTrace.empty);
      await settle();
      expect(delivered, isEmpty);
      online = true;
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(delivered, ['Bad state: one', 'Bad state: two']);
      sink.dispose();
    },
  );

  test('a 5xx is retried, a 400 is not', () async {
    final codes = [503, 202, 400];
    var calls = 0;
    final sink = sinkWith((r) async {
      calls += 1;
      return http.Response('', codes.removeAt(0));
    });
    sink.record(StateError('a'), StackTrace.empty);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(calls, 2);
    sink.record(StateError('b'), StackTrace.empty);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(calls, 3);
    sink.dispose();
  });

  test('retries stop after maxAttempts and the queue stays bounded', () async {
    var calls = 0;
    final sink = HttpObservabilitySink(
      baseUrl: 'https://api.movera.example',
      client: MockClient((r) async {
        calls += 1;
        return http.Response('', 500);
      }),
      queueLimit: 3,
      retryDelay: const Duration(milliseconds: 1),
      maxRetryDelay: const Duration(milliseconds: 2),
      maxAttempts: 2,
    );
    for (var i = 0; i < 10; i++) {
      sink.record(StateError('e$i'), StackTrace.empty);
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(calls, lessThanOrEqualTo(8));
    expect(sink.droppedCount, greaterThanOrEqualTo(7));
    sink.dispose();
  });

  test('the body never passes 16 KB nor the field limits', () {
    final body = CrashReport.body(
      error: 'e' * 20000,
      stackTrace: StackTrace.fromString('#0 frame\n' * 5000),
      extra: {'blob': 'x' * 20000},
      app: 'rider',
      appVersion: 'v' * 100,
      occurredAt: DateTime.utc(2026),
    );
    expect(utf8.encode(jsonEncode(body)).length, lessThanOrEqualTo(16384));
    expect((body['error'] as String).length, lessThanOrEqualTo(4000));
    expect((body['stack'] as String).length, lessThanOrEqualTo(12000));
    expect((body['appVersion'] as String).length, 40);
  });

  test('a failing sink never throws into the app', () async {
    final sink = sinkWith((r) async => throw StateError('boom'));
    sink.record(_Exploding(), StackTrace.empty);
    sink.record(StateError('ok'), StackTrace.empty);
    await settle();
    sink.dispose();
    sink.record(StateError('after dispose'), StackTrace.empty);
  });

  test('helpers: platform, version split, screen without ids', () {
    expect(CrashReport.platformName(isWeb: true), 'web');
    expect(
      CrashReport.platformName(isWeb: false, platform: TargetPlatform.iOS),
      'ios',
    );
    expect(
      CrashReport.platformName(isWeb: false, platform: TargetPlatform.android),
      'android',
    );
    expect(
      CrashReport.platformName(isWeb: false, platform: TargetPlatform.linux),
      isNull,
    );
    expect(CrashReport.splitVersion('1.0.0+1'), (version: '1.0.0', build: '1'));
    expect(CrashReport.splitVersion('dev'), (version: 'dev', build: null));
    expect(CrashReport.splitVersion('2.0.0+'), (version: '2.0.0', build: null));
    expect(CrashReport.cleanScreen('/trip/0b9f3c2e-77aa?x=1'), '/trip/:id');
    expect(CrashReport.cleanScreen(null), isNull);
    expect(CrashReport.cleanScreen('???'), isNull);
    expect(CrashReport.cleanScreen('z' * 200)!.length, 80);
  });

  test('CrashReporter: fatal is crash, a caught error is error', () {
    final seen = <Map<String, Object?>>[];
    Observability.configure(crashSink: _Recording(seen));
    addTearDown(Observability.reset);
    const reporter = CrashReporter();
    reporter.record(StateError('a'), StackTrace.empty, fatal: true);
    reporter.record(StateError('b'), StackTrace.empty, screen: 'wallet');
    expect(seen[0]['kind'], 'crash');
    expect(seen[1]['kind'], 'error');
    expect(seen[1]['screen'], 'wallet');
  });
}

class _Exploding {
  @override
  String toString() => throw StateError('toString failed');
}

class _Recording implements CrashSink {
  _Recording(this.seen);
  final List<Map<String, Object?>> seen;

  @override
  void record(
    Object error,
    StackTrace stackTrace, {
    Map<String, Object?> extra = const {},
  }) => seen.add(extra);
}
