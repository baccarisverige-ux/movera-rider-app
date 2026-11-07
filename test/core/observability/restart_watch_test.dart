import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/core/observability/crash_report.dart';
import 'package:movera_rider/core/observability/restart_watch.dart';
import 'package:movera_rider/core/observability/http_observability.dart';
import 'package:movera_rider/features/ride_booking/application/ride_session.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/app/router/home_history_observer.dart';

class _FakeStore implements RestartMarkerStore {
  String? value;

  @override
  String? read() => value;

  @override
  void write(String value) => this.value = value;

  Map<String, Object?> get marker =>
      (jsonDecode(value!) as Map).cast<String, Object?>();
}

String _marker({
  required DateTime start,
  required DateTime beat,
  String? screen = '/ride/active',
  String? stage = 'onTrip',
  bool visible = true,
  bool clean = false,
}) => jsonEncode({
  'v': 1,
  'id': 'abcd0123',
  'start': start.millisecondsSinceEpoch,
  'beat': beat.millisecondsSinceEpoch,
  'screen': screen,
  'stage': stage,
  'visible': visible,
  'clean': clean,
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final start = DateTime.utc(2026, 11, 7, 12);
  final lastBeat = start.add(const Duration(seconds: 95));
  final now = lastBeat.add(const Duration(seconds: 3));

  late _FakeStore store;
  late List<String> reports;
  late String? screen;

  RestartWatch watch({DateTime? at}) => RestartWatch(
    store: store,
    report: reports.add,
    screen: () => screen,
    clock: () => at ?? now,
  );

  setUp(() {
    store = _FakeStore();
    reports = [];
    screen = '/home';
    RestartWatch.instance = null;
    RestartWatch.tripStage = null;
  });

  tearDown(() {
    RestartWatch.instance?.stop();
    RestartWatch.instance = null;
    RestartWatch.tripStage = null;
  });

  test('previous session unclean, visible and recent: one report with the '
      'last screen', () {
    store.value = _marker(start: start, beat: lastBeat);

    watch().start(visible: true, periodic: false);

    expect(reports, [
      'unexpected restart: last screen /ride/active (trip stage '
          'onTrip), 3 s after last beat, uptime 95 s',
    ]);
  });

  test('clean, hidden, old or missing previous marker: no report', () {
    for (final previous in <String?>[
      _marker(start: start, beat: lastBeat, clean: true),
      _marker(start: start, beat: lastBeat, visible: false),
      _marker(start: start, beat: now.subtract(const Duration(minutes: 11))),
      null,
      'not json',
    ]) {
      store.value = previous;
      watch().start(visible: true, periodic: false);
    }

    expect(reports, isEmpty);
  });

  test('the new marker is written at start and pagehide marks it clean', () {
    watch().start(visible: true, periodic: false);
    expect(store.marker['clean'], false);
    expect(store.marker['visible'], true);
    expect(store.marker['screen'], '/home');

    final w = watch()..start(visible: true, periodic: false);
    w.pageHide();
    expect(store.marker['clean'], true);
    expect(RestartWatch.unexpectedRestart(store.value, now), isNull);
  });

  test('the marker is updated on a screen change and a trip stage change', () {
    RestartWatch.instance = watch()..start(visible: true, periodic: false);
    expect(store.marker['screen'], '/home');

    screen = '/ride/active';
    RestartWatch.touch();
    expect(store.marker['screen'], '/ride/active');

    final ride = RideSession()..localTransition(RideStatus.pickupSelected);
    expect(store.marker['stage'], 'pickupSelected');
    ride.reset();
    expect(store.marker['stage'], isNull);
  });

  test('the route observer updates the marker on a push', () {
    RestartWatch.instance = RestartWatch(
      store: store,
      report: reports.add,
      clock: () => now,
    )..start(visible: true, periodic: false);
    final route = PageRouteBuilder<void>(
      settings: const RouteSettings(name: '/wallet'),
      pageBuilder: (_, _, _) => const SizedBox(),
    );

    HomeHistoryObserver().didPush(route, null);

    expect(CrashReport.currentScreen, '/wallet');
    expect(store.marker['screen'], '/wallet');
  });

  test('a lost WebGL context is reported once', () {
    final w = watch()..start(visible: true, periodic: false);
    w.contextLost();
    w.contextLost();
    expect(reports, ['webgl context lost: last screen /home, uptime 0 s']);
  });

  test('a report goes out as one error on the crash report channel', () async {
    final sent = <Map<String, Object?>>[];
    final sink = HttpObservabilitySink(
      baseUrl: 'https://api.example.test',
      client: MockClient((request) async {
        sent.add((jsonDecode(request.body) as Map).cast<String, Object?>());
        return http.Response('', 202);
      }),
      platform: 'web',
    );
    store.value = _marker(start: start, beat: lastBeat, stage: null);

    RestartWatch(
      store: store,
      report: (message) => sink.record(
        message,
        StackTrace.empty,
        extra: const {'kind': CrashReport.kindError},
      ),
      clock: () => now,
    ).start(visible: true, periodic: false);
    await Future<void>.delayed(Duration.zero);

    expect(sent, hasLength(1));
    expect(sent.single['kind'], 'error');
    expect(sent.single['app'], 'rider');
    expect(
      sent.single['error'],
      'unexpected restart: last screen /ride/active, 3 s after last beat, '
      'uptime 95 s',
    );
    sink.dispose();
  });
}
