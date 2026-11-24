import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/core/config/rider_app_config.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/core/observability/crash_breadcrumbs.dart';
import 'package:movera_rider/core/observability/crash_catcher.dart';
import 'package:movera_rider/core/observability/crash_files.dart';
import 'package:movera_rider/core/observability/crash_report.dart';
import 'package:movera_rider/core/observability/http_observability.dart';

/// Owner 2026-11-24 "Add to admin all kind of crash" (contract v0.18.157
/// `contract.json#crashCatcher`). Rule 36: fails on main — there is no
/// crash catcher, no native_crash / freeze / dart_error kind, no
/// breadcrumbs, no outbox file and no crashReports.on switch.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 30));

  late DateTime now;
  setUp(() {
    now = DateTime.utc(2026, 11, 24, 10);
    CrashReport.reportingEnabled = true;
    CrashReport.context = null;
    CrashReport.currentScreen = null;
    CrashBreadcrumbs.instance = CrashBreadcrumbs(clock: () => now);
  });

  CrashCatcher catcherWith(MemoryCrashFiles files, List<CrashEvent> events) =>
      CrashCatcher(
        files: files,
        send: events.add,
        clock: () => now,
        appVersion: '1.0.0',
        build: '7',
      );

  group('native crash at the next launch (running marker)', () {
    test(
      'a marker left by the last run + the iOS exception file = one native_crash with reason, stack, last screen and breadcrumbs',
      () {
        final files = MemoryCrashFiles();
        final first = catcherWith(files, []);
        first.start();
        expect(
          files.read(CrashFileNames.running),
          contains('"appVersion":"1.0.0"'),
        );
        first.crumbs.route('/home');
        first.crumbs.network(
          'GET',
          '/rider/trips/trp_01JB2Z3Y4X5W6V7T8S9R0QPNMK',
          503,
        );
        first.stop();
        // The process dies here: no pause, the marker stays. iOS wrote the exception.
        files.write(
          CrashFileNames.native,
          jsonEncode({
            'name': 'NSInvalidArgumentException',
            'reason': 'Configure: invalid GOOGLE_APP_ID',
            'stack': '0 CoreFoundation __exceptionPreprocess',
          }),
        );
        final events = <CrashEvent>[];
        CrashBreadcrumbs.instance = CrashBreadcrumbs(clock: () => now);
        catcherWith(files, events).start();
        expect(events, hasLength(1));
        final e = events.single;
        expect(e.kind, 'native_crash');
        expect(
          e.message,
          'NSInvalidArgumentException: Configure: invalid GOOGLE_APP_ID',
        );
        expect(e.nativeReason, {
          'name': 'NSInvalidArgumentException',
          'reason': 'Configure: invalid GOOGLE_APP_ID',
        });
        expect(e.stack, contains('__exceptionPreprocess'));
        expect(e.screen, '/home');
        expect(e.breadcrumbs!.map((c) => c['message']), [
          '/home',
          'GET /rider/trips/:id 503',
        ]);
        expect(
          files.read(CrashFileNames.native),
          isNull,
          reason: 'the native file is read once',
        );
        expect(
          files.read(CrashFileNames.running),
          isNotNull,
          reason: 'the new run has its marker',
        );
      },
    );

    test(
      'a marker with no native file (Flutter engine / signal / OS kill) still reports, naming the last screen',
      () {
        final files = MemoryCrashFiles()
          ..write(
            CrashFileNames.running,
            '{"startedAt":"2026-11-24T09:00:00Z"}',
          );
        files.write(
          CrashFileNames.breadcrumbs,
          jsonEncode([
            {
              'at': '2026-11-24T09:59:00Z',
              'type': 'route',
              'message': '/finding',
            },
          ]),
        );
        final events = <CrashEvent>[];
        catcherWith(files, events).start();
        expect(events.single.kind, 'native_crash');
        expect(
          events.single.message,
          'App ended without a clean exit (last screen /finding)',
        );
        expect(events.single.nativeReason, isNull);
      },
    );

    test(
      'going to the background deletes the marker: a later swipe-away is not a crash',
      () {
        final files = MemoryCrashFiles();
        final first = catcherWith(files, []);
        first.start();
        first.lifecycle(AppLifecycleState.inactive);
        expect(files.read(CrashFileNames.running), isNotNull);
        first.lifecycle(AppLifecycleState.paused);
        expect(files.read(CrashFileNames.running), isNull);
        first.stop();
        final events = <CrashEvent>[];
        catcherWith(files, events).start();
        expect(events, isEmpty);
      },
    );

    test('back in front writes the marker again', () {
      final files = MemoryCrashFiles();
      final c = catcherWith(files, [])..start();
      c.lifecycle(AppLifecycleState.paused);
      c.lifecycle(AppLifecycleState.resumed);
      expect(files.read(CrashFileNames.running), isNotNull);
      c.stop();
    });

    test('the web keeps no marker', () {
      final files = MemoryCrashFiles()..write(CrashFileNames.running, '{}');
      final events = <CrashEvent>[];
      CrashCatcher(
        files: files,
        send: events.add,
        clock: () => now,
        markerSupported: false,
      ).start();
      expect(events, isEmpty);
    });
  });

  group('freeze watch', () {
    test(
      'no tick for 7 s while in front = one freeze report with how long and the screen',
      () {
        final events = <CrashEvent>[];
        final c = catcherWith(MemoryCrashFiles(), events)..start();
        CrashReport.currentScreen = '/home';
        now = now.add(const Duration(seconds: 1));
        c.checkFreeze();
        expect(events, isEmpty);
        now = now.add(const Duration(seconds: 8));
        c.checkFreeze();
        expect(events.single.kind, 'freeze');
        expect(events.single.freezeMs, 7000);
        expect(
          events.single.message,
          'The screen froze for 7 s (screen /home)',
        );
        c.stop();
      },
    );

    test('a gap under 5 s, or while in the background, is no freeze', () {
      final events = <CrashEvent>[];
      final c = catcherWith(MemoryCrashFiles(), events)..start();
      now = now.add(const Duration(seconds: 5));
      c.checkFreeze();
      c.lifecycle(AppLifecycleState.paused);
      now = now.add(const Duration(minutes: 10));
      c.checkFreeze();
      expect(events, isEmpty);
      c.stop();
    });
  });

  group('breadcrumbs', () {
    test(
      'keeps the last 30, scrubbed and cut to 200 characters; ids out of paths',
      () {
        final b = CrashBreadcrumbs(clock: () => now);
        for (var i = 0; i < 35; i++) {
          b.add('log', 'line $i');
        }
        expect(b.items, hasLength(30));
        expect(b.items.first.message, 'line 5');
        b.add('log', 'call +46 70 174 06 08 or anna@example.com ${'x' * 300}');
        expect(b.items.last.message, isNot(contains('174 06 08')));
        expect(b.items.last.message, isNot(contains('anna@example.com')));
        expect(b.items.last.message.length, 200);
        b.add('tap', 'not a type');
        expect(b.items.last.type, 'log');
        b.network('post', '/trips/123/cancel?x=1', 409);
        expect(b.items.last.message, 'POST /trips/:id/cancel 409');
      },
    );

    test(
      'a failed API call and a warning log line become breadcrumbs; an answered call does not',
      () {
        AppLog.info('api.GET', extra: {'path': '/rider/config', 'status': 200});
        AppLog.info(
          'api.GET',
          extra: {'path': '/rider/trips/42', 'status': 503},
        );
        AppLog.error('api.timeout', extra: {'path': '/rider/trips/active'});
        AppLog.warning('push.register_failed');
        expect(
          CrashBreadcrumbs.instance.items.map((c) => '${c.type} ${c.message}'),
          [
            'network GET /rider/trips/:id 503',
            'network CALL /rider/trips/active timeout',
            'log warning push.register_failed',
          ],
        );
      },
    );
  });

  group('the report body (v0.18.157 fields)', () {
    test(
      'kinds dart_error, native_crash and freeze are kept; an unknown kind is crash',
      () {
        for (final kind in [
          'dart_error',
          'native_crash',
          'freeze',
          'error',
          'crash',
        ]) {
          final body = CrashReport.body(
            error: 'x',
            stackTrace: StackTrace.empty,
            app: 'rider',
            kind: kind,
            occurredAt: now,
          );
          expect(body['kind'], kind);
        }
        expect(
          CrashReport.body(
            error: 'x',
            stackTrace: StackTrace.empty,
            app: 'rider',
            kind: 'panic',
            occurredAt: now,
          )['kind'],
          'crash',
        );
      },
    );

    test(
      'carries device, OS, trip, zone, breadcrumbs, native reason and freeze time, scrubbed, within 16 KB',
      () {
        final body = CrashReport.body(
          error: 'boom',
          stackTrace: StackTrace.fromString('x' * 20000),
          app: 'rider',
          kind: 'native_crash',
          occurredAt: now,
          osVersion: 'iOS 17.1',
          deviceModel: 'iPhone15,2',
          tripId: 'trp_01JB2Z3Y4X5W6V7T8S9R0QPNMK',
          zoneId: 'Z001',
          breadcrumbs: [
            for (var i = 0; i < 40; i++)
              {
                'at': '2026-11-24T09:59:00Z',
                'type': 'log',
                'message': 'call +46 70 174 06 08 $i',
              },
          ],
          nativeReason: {'name': 'SIGABRT', 'reason': 'signal 6'},
          freezeMs: 0,
          extra: {'breadcrumbs': 'never in extra'},
        );
        expect(body['osVersion'], 'iOS 17.1');
        expect(body['deviceModel'], 'iPhone15,2');
        expect(body['tripId'], 'trp_01JB2Z3Y4X5W6V7T8S9R0QPNMK');
        expect(body['zoneId'], 'Z001');
        expect(body['nativeReason'], {'name': 'SIGABRT', 'reason': 'signal 6'});
        expect(body['freezeMs'], 0);
        expect((body['breadcrumbs']! as List).length, lessThanOrEqualTo(30));
        expect(jsonEncode(body), isNot(contains('174 06 08')));
        expect((body['extra']! as Map).containsKey('breadcrumbs'), isFalse);
        expect(
          utf8.encode(jsonEncode(body)).length,
          lessThanOrEqualTo(CrashReport.maxBytes),
        );
      },
    );
  });

  group('sink: switch, context and outbox', () {
    HttpObservabilitySink sinkWith(
      Future<http.Response> Function(http.Request) handler,
    ) => HttpObservabilitySink(
      baseUrl: 'https://api.movera.example',
      client: MockClient(handler),
      appVersion: '1.0.0',
      build: '7',
      platform: 'ios',
      retryDelay: const Duration(milliseconds: 20),
      maxAttempts: 2,
    );

    test('crashReports.on off: nothing is sent; on again: sent', () async {
      final sent = <http.Request>[];
      final sink = sinkWith((r) async {
        sent.add(r);
        return http.Response('', 202);
      });
      CrashReport.reportingEnabled = false;
      sink.record(
        StateError('off'),
        StackTrace.empty,
        extra: const {'kind': 'dart_error'},
      );
      await settle();
      expect(sent, isEmpty);
      CrashReport.reportingEnabled = true;
      sink.record(
        StateError('on'),
        StackTrace.empty,
        extra: const {'kind': 'dart_error'},
      );
      await settle();
      expect(sent, hasLength(1));
      sink.dispose();
    });

    test(
      'a report carries the catcher context (device, OS, breadcrumbs) and the native fields from extra',
      () async {
        final sent = <Map<String, Object?>>[];
        final sink = sinkWith((r) async {
          sent.add(jsonDecode(r.body) as Map<String, Object?>);
          return http.Response('', 202);
        });
        CrashBreadcrumbs.instance.route('/home');
        CrashReport.context = () => {
          'deviceModel': 'iPhone15,2',
          'osVersion': 'iOS 17.1',
          'breadcrumbs': CrashBreadcrumbs.instance.toJson(),
        };
        sink.record(
          'NSInvalidArgumentException: bad',
          StackTrace.empty,
          extra: const {
            'kind': 'native_crash',
            'nativeReason': {
              'name': 'NSInvalidArgumentException',
              'reason': 'bad',
            },
          },
        );
        await settle();
        expect(sent.single, containsPair('kind', 'native_crash'));
        expect(sent.single, containsPair('deviceModel', 'iPhone15,2'));
        expect(sent.single, containsPair('osVersion', 'iOS 17.1'));
        expect(sent.single['nativeReason'], {
          'name': 'NSInvalidArgumentException',
          'reason': 'bad',
        });
        expect(
          (sent.single['breadcrumbs']! as List).single,
          containsPair('message', '/home'),
        );
        sink.dispose();
      },
    );

    test(
      'offline: the report stays in the outbox file and the next launch sends it once, then it is gone',
      () async {
        final files = MemoryCrashFiles();
        final offline = sinkWith(
          (r) async => throw http.ClientException('offline'),
        )..outbox = CrashOutbox(files);
        offline.record(
          StateError('kept'),
          StackTrace.empty,
          extra: const {'kind': 'dart_error'},
        );
        await Future<void>.delayed(const Duration(milliseconds: 150));
        offline.dispose();
        expect(CrashOutbox(files).pending(), hasLength(1));
        final sent = <Map<String, Object?>>[];
        final online = sinkWith((r) async {
          sent.add(jsonDecode(r.body) as Map<String, Object?>);
          return http.Response('', 202);
        })..outbox = CrashOutbox(files);
        online.resendOutbox();
        await settle();
        expect(sent.single['error'], contains('kept'));
        expect(CrashOutbox(files).pending(), isEmpty);
        online.dispose();
      },
    );

    test('the outbox keeps at most 20', () {
      final box = CrashOutbox(MemoryCrashFiles());
      for (var i = 0; i < 25; i++) {
        box.add({'error': '$i'});
      }
      expect(box.pending().map((p) => p.body['error']), [
        for (var i = 5; i < 25; i++) '$i',
      ]);
    });
  });

  test('the zone switch is read from the rider document (on when missing)', () {
    Map<String, Object?> doc(Object? crashReports) => {
      'version': 2,
      'publishedAt': '2026-11-01T00:00:00Z',
      'zoneId': 'Z001',
      'currency': 'SEK',
      'timeZone': 'Europe/Stockholm',
      'crashReports': ?crashReports,
    };
    expect(
      RiderAppConfig.fromJson(doc({'on': false}))!.crashReportsOn,
      isFalse,
    );
    expect(RiderAppConfig.fromJson(doc({'on': true}))!.crashReportsOn, isTrue);
    expect(RiderAppConfig.fromJson(doc(null))!.crashReportsOn, isTrue);
  });

  test(
    'the switch is kept on the phone for the next start (a crash before the document is read)',
    () {
      final files = MemoryCrashFiles();
      final c = catcherWith(files, []);
      expect(c.reportingOn, isTrue);
      c.reportingOn = false;
      expect(CrashReport.reportingEnabled, isFalse);
      CrashReport.reportingEnabled = true;
      catcherWith(files, []).start();
      expect(CrashReport.reportingEnabled, isFalse);
    },
  );
}
