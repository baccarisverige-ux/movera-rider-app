import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/observability/restart_watch.dart';

class _Store implements RestartMarkerStore {
  String? value;
  @override
  String? read() => value;
  @override
  void write(String v) => value = v;
}

/// S8 R3 + proof5 (2026-11-07): the rider and driver web apps share one
/// origin. Before this fix both kept the marker under
/// 'movera.restart_watch.v1', so each read the other's marker, and one
/// `pagehide` marked the session clean forever (a later kill was silent).
/// One shared store stands for the origin's localStorage; the watch built
/// with app 'driver' stands for the driver app.
void main() {
  final t0 = DateTime.utc(2026, 11, 7, 15, 24, 58);

  test('the rider keeps its own storage key', () {
    expect(RestartWatch.storageKey, 'movera.restart_watch.rider.v1');
    expect(RestartWatch.appName, 'rider');
  });

  test('every marker names its app', () {
    final store = _Store();
    RestartWatch(
      store: store,
      report: (_) {},
      clock: () => t0,
      screen: () => '/home',
    ).start(visible: true, periodic: false);
    expect((jsonDecode(store.value!) as Map)['app'], 'rider');
  });

  test('PROOF B: the other app booting on the same store does not report '
      'the rider page as its own restart', () {
    final shared = _Store();
    var now = t0;
    final driverReports = <String>[];
    final rider = RestartWatch(
      store: shared,
      report: (_) {},
      clock: () => now,
      screen: () => '/ride/finding',
    );
    RestartWatch.tripStage = 'findingDriver';
    rider.start(visible: true, periodic: false);
    now = now.add(const Duration(seconds: 10));
    rider.beat();
    RestartWatch.tripStage = null;
    now = now.add(const Duration(seconds: 2));
    RestartWatch(
      store: shared,
      report: driverReports.add,
      clock: () => now,
      screen: () => '/home',
      app: 'driver',
    ).start(visible: true, periodic: false);
    expect(driverReports, isEmpty, reason: 'driver reported: $driverReports');
  });

  test('a marker with no app (the old shared key format) is not read', () {
    final old = jsonEncode({
      'v': 1,
      'id': 'abcd0123',
      'start': t0.millisecondsSinceEpoch,
      'beat': t0.millisecondsSinceEpoch,
      'screen': '/ride/finding',
      'visible': true,
      'clean': false,
    });
    expect(
      RestartWatch.unexpectedRestart(old, t0.add(const Duration(seconds: 3))),
      isNull,
    );
  });

  test('a clean start of the other app does not report the rider (still '
      'running in the background)', () {
    final store = _Store();
    var t = DateTime.utc(2026, 11, 7, 15);
    final reportsB = <String>[];
    final a = RestartWatch(
      store: store,
      report: (_) {},
      screen: () => '/ride/finding',
      clock: () => t,
    )..start(visible: true, periodic: false);
    t = t.add(const Duration(seconds: 5));
    a.setVisible(false);
    t = t.add(const Duration(seconds: 3));
    RestartWatch(
      store: store,
      report: reportsB.add,
      screen: () => '/home',
      clock: () => t,
      app: 'driver',
    ).start(visible: true, periodic: false);
    expect(reportsB, isEmpty, reason: 'B reported: $reportsB');
  });

  test('PROOF A: a kill after a pagehide and a later visible beat is '
      'reported', () {
    final store = _Store();
    var now = t0;
    final reports = <String>[];
    final w = RestartWatch(
      store: store,
      report: reports.add,
      clock: () => now,
      screen: () => '/ride/finding',
    )..start(visible: true, periodic: false);
    now = now.add(const Duration(seconds: 5));
    w.pageHide();
    now = now.add(const Duration(seconds: 5));
    w.setVisible(true);
    now = now.add(const Duration(seconds: 60));
    w.beat();
    now = now.add(const Duration(seconds: 2));
    RestartWatch(
      store: store,
      report: reports.add,
      clock: () => now,
    ).start(visible: true, periodic: false);
    expect(reports, isNotEmpty);
  });

  test('visible again after a pagehide clears clean at once (iOS resume '
      'without pageshow)', () {
    final store = _Store();
    var t = t0;
    final w = RestartWatch(
      store: store,
      report: (_) {},
      screen: () => '/ride/waiting',
      clock: () => t,
    )..start(visible: true, periodic: false);
    w.setVisible(false);
    w.pageHide();
    expect((jsonDecode(store.value!) as Map)['clean'], true);
    t = t.add(const Duration(seconds: 20));
    w.setVisible(true);
    expect((jsonDecode(store.value!) as Map)['clean'], false);
    t = t.add(const Duration(seconds: 10));
    final next = <String>[];
    RestartWatch(
      store: store,
      report: next.add,
      clock: () => t,
    ).start(visible: true, periodic: false);
    expect(next, isNotEmpty);
  });

  test('a pagehide while hidden stays clean: a real close is not reported', () {
    final store = _Store();
    var t = t0;
    final w = RestartWatch(store: store, report: (_) {}, clock: () => t)
      ..start(visible: true, periodic: false);
    w.setVisible(false);
    w.pageHide();
    w.beat();
    t = t.add(const Duration(seconds: 30));
    final next = <String>[];
    RestartWatch(
      store: store,
      report: next.add,
      clock: () => t,
    ).start(visible: true, periodic: false);
    expect(next, isEmpty);
  });

  test('pagehide into the back/forward cache is recorded on its own', () {
    final store = _Store();
    final w = RestartWatch(store: store, report: (_) {}, clock: () => t0)
      ..start(visible: true, periodic: false);
    w.setVisible(false);
    w.pageHide(persisted: true);
    final marker = jsonDecode(store.value!) as Map;
    expect(marker['hidePersisted'], true);
    expect(marker['clean'], true);
    w.pageShow();
    expect(
      (jsonDecode(store.value!) as Map).containsKey('hidePersisted'),
      isFalse,
    );
  });
}
