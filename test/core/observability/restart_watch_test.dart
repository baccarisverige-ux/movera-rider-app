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
  DateTime? hidden,
}) => jsonEncode({
  'v': 1,
  'id': 'abcd0123',
  'start': start.millisecondsSinceEpoch,
  'beat': beat.millisecondsSinceEpoch,
  'screen': screen,
  'stage': stage,
  'visible': visible,
  'clean': clean,
  if (hidden != null) 'hidden': hidden.millisecondsSinceEpoch,
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
      'unexpected restart (on screen): last screen /ride/active (trip '
          'stage onTrip), 3 s after last beat, uptime 95 s',
    ]);
  });

  // Owner decision Q5 (2026-11-07, "Report background too (Recommended)"):
  // a page iOS killed while it was in the background (the app was switched
  // away, so its last beat says visible:false, and iOS sends no pagehide on
  // a kill; finding D6) is reported too, marked background, with the last
  // screen and the time away. Earlier this test pinned "hidden: no report".
  test('previous session unclean, hidden and recent: one background report '
      'with the last screen and the time away', () {
    store.value = _marker(
      start: start,
      beat: lastBeat,
      visible: false,
      hidden: lastBeat.subtract(const Duration(seconds: 40)),
    );

    watch().start(visible: true, periodic: false);

    expect(reports, [
      'unexpected restart (background): last screen /ride/active (trip '
          'stage onTrip), away 43 s, 3 s after last beat, uptime 95 s',
    ]);
  });

  test('a hidden marker from before the hidden time was kept counts the '
      'time away from its last beat', () {
    expect(
      RestartWatch.unexpectedRestart(
        _marker(start: start, beat: lastBeat, visible: false, stage: null),
        now,
      ),
      'unexpected restart (background): last screen /ride/active, away 3 s, '
      '3 s after last beat, uptime 95 s',
    );
  });

  // Owner decision (2026-11-07, on #533): on-screen restarts keep the
  // 10 min limit; background restarts are reported up to 2 hours.
  test('a background restart 20 min after the last beat is reported; an '
      'on-screen one is not', () {
    final later = lastBeat.add(const Duration(minutes: 20));
    expect(
      RestartWatch.unexpectedRestart(
        _marker(
          start: start,
          beat: lastBeat,
          visible: false,
          stage: null,
          hidden: lastBeat.subtract(const Duration(seconds: 10)),
        ),
        later,
      ),
      'unexpected restart (background): last screen /ride/active, away '
      '1210 s, 1200 s after last beat, uptime 95 s',
    );
    expect(
      RestartWatch.unexpectedRestart(
        _marker(start: start, beat: lastBeat),
        later,
      ),
      isNull,
    );
  });

  test('a background restart 2 hours or more after the last beat is not '
      'reported', () {
    expect(
      RestartWatch.unexpectedRestart(
        _marker(start: start, beat: lastBeat, visible: false),
        lastBeat.add(const Duration(hours: 2)),
      ),
      isNull,
    );
    expect(
      RestartWatch.unexpectedRestart(
        _marker(start: start, beat: lastBeat, visible: false),
        lastBeat.add(const Duration(hours: 1, minutes: 59)),
      ),
      isNotNull,
    );
  });

  test('the marker keeps when the page went to the background', () {
    final later = now.add(const Duration(seconds: 5));
    var at = now;
    final w = RestartWatch(
      store: store,
      report: reports.add,
      screen: () => screen,
      clock: () => at,
    )..start(visible: true, periodic: false);
    expect(store.marker.containsKey('hidden'), isFalse);
    w.setVisible(false);
    expect(store.marker['hidden'], now.millisecondsSinceEpoch);
    at = later;
    w.beat();
    w.setVisible(false);
    expect(store.marker['hidden'], now.millisecondsSinceEpoch);
    w.setVisible(true);
    expect(store.marker.containsKey('hidden'), isFalse);
  });

  test('clean, old or missing previous marker: no report', () {
    for (final previous in <String?>[
      _marker(start: start, beat: lastBeat, clean: true),
      _marker(start: start, beat: lastBeat, visible: false, clean: true),
      _marker(start: start, beat: now.subtract(const Duration(minutes: 11))),
      _marker(
        start: start,
        beat: now.subtract(const Duration(hours: 2, minutes: 1)),
        visible: false,
      ),
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
      'unexpected restart (on screen): last screen /ride/active, 3 s after '
      'last beat, uptime 95 s',
    );
    sink.dispose();
  });
}
