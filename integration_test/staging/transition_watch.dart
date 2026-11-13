import 'package:flutter/foundation.dart' show kDebugMode, kProfileMode;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/finding_driver/presentation/finding_drivers.dart';
import 'package:movera_rider/features/home/presentation/home.dart';
import 'package:movera_rider/features/pickup/presentation/set_pickup_page.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';

import 'check_log.dart';
import 'recording_client.dart';
import 'rider_session.dart';
import 'rider_steps.dart';

/// Owner 2026-11-12 ("can you check if screens change smoothly without any
/// big reload or any problem?"), rider app on the phone (G31 rider): every
/// screen change gets three checks, as in the driver suite:
///
/// * `TRANSITION:<name>:SMOOTH`  engine FrameTiming while it runs: FAIL
///   when one frame takes > [freezeMs] ms or, with at least
///   [minFramesForRatio] frames, more than [missedLimit] miss 16.7 ms.
/// * `TRANSITION:<name>:RELOAD`  FAIL when a map a screen keeps is created
///   again: a new GoogleMap State for the same screen, or the app's map
///   provider (`AppScope.instance.maps`) counting a new map
///   (`generation` up) while the same screen owns the map
///   (`activeOwner` unchanged: G25 "the map survives screen switches");
///   or a full-screen loader (`start-spinner`, `deferred-screen-loading`,
///   a spinner centred in >= 60 % of the screen) or a blank frame (no
///   Scaffold). GET reads are counted; the same read twice within 4 s in
///   the change's first 8 s is a FAIL too (a screen that reloads its data).
/// * `TRANSITION:<name>:ERRORS`  FAIL on any 4xx/5xx or failed call of the
///   app (answers the step expects excepted, and listed), a Flutter
///   exception, or a crash report the app sent to its own sink
///   (`POST /api/v1/telemetry/crash…`).
///
/// The phone runs a DEBUG build, so frame numbers are indicative.
class TransitionWatch {
  TransitionWatch(this.tester, this.log, this.session);

  static const int freezeMs = 200;
  static const double missedLimit = 0.20;
  static const int minFramesForRatio = 10;
  static const Duration repeatWindow = Duration(seconds: 4);
  static const Duration settleWindow = Duration(seconds: 8);
  static const Duration _budget = Duration(microseconds: 16667);

  final WidgetTester tester;
  final CheckLog log;
  final RiderSession session;

  RecordingClient get rec => session.rec;

  final List<Map<String, Object?>> rows = <Map<String, Object?>>[];

  Set<int>? _homeBaseline;

  static String get buildMode => kDebugMode
      ? 'debug build, indicative'
      : kProfileMode
      ? 'profile build'
      : 'release build';

  /// GoogleMap State ids per rider screen, offstage routes included.
  Map<String, Set<int>> mapStates() {
    final out = <String, Set<int>>{};
    for (final e in find.byType(GoogleMap, skipOffstage: false).evaluate()) {
      if (e is! StatefulElement) continue;
      final owner = e.findAncestorWidgetOfExactType<WaitingForDriver>() != null
          ? 'trip'
          : e.findAncestorWidgetOfExactType<FindingDrivers>() != null
          ? 'finding'
          : e.findAncestorWidgetOfExactType<SetPickupPage>() != null
          ? 'set-pickup'
          : e.findAncestorWidgetOfExactType<SelectRide>() != null
          ? 'select-ride'
          : e.findAncestorWidgetOfExactType<Home>() != null
          ? 'home'
          : 'other';
      (out[owner] ??= <int>{}).add(identityHashCode(e.state));
    }
    return out;
  }

  /// Call once Home shows, before the first transition.
  void baseline() => _homeBaseline = mapStates()['home'];

  /// Runs [body] as the transition [name] and logs its three checks.
  /// [expected]: failed answers this step expects, as (status, a part of
  /// the path), e.g. `(409, '/call')` for call_busy: listed, not a FAIL.
  Future<T> run<T>(
    String name,
    Future<T> Function() body, {
    List<(int, String)> expected = const <(int, String)>[],
  }) async {
    final frames = <FrameTiming>[];
    void onTimings(List<FrameTiming> t) => frames.addAll(t);
    final mark = rec.length;
    final exMark = session.appExceptions.length;
    final before = mapStates();
    final maps = AppScope.instance.maps;
    final genBefore = maps.generation;
    final ownerBefore = maps.activeOwner;
    var blank = 0, loader = 0;
    _loaderIn.clear();
    final previousProbe = pumpProbe;
    pumpProbe = () {
      previousProbe?.call();
      if (!shows(find.byType(Scaffold))) blank++;
      if (_fullScreenLoader()) loader++;
    };
    SchedulerBinding.instance.addTimingsCallback(onTimings);
    try {
      return await body();
    } finally {
      // The engine hands timings over in batches: let the last ones come.
      await wait(tester, const Duration(milliseconds: 1200));
      SchedulerBinding.instance.removeTimingsCallback(onTimings);
      pumpProbe = previousProbe;
      final exceptions = <String>[
        ...session.appExceptions.skip(exMark),
        for (var i = 0; i < 5; i++)
          if (tester.takeException() case final Object e)
            e.runtimeType.toString(),
      ];
      final generationUp = maps.generation - genBefore;
      final ownerAfter = maps.activeOwner;
      _report(
        name,
        frames,
        mark,
        before,
        mapStates(),
        blank,
        loader,
        exceptions,
        expected,
        sameOwnerNewMap:
            generationUp > 0 && ownerBefore != null && ownerBefore == ownerAfter
            ? '$ownerAfter (+$generationUp)'
            : null,
        owners: '$ownerBefore -> $ownerAfter gen +$generationUp',
      );
    }
  }

  /// The screens that showed a full-screen spinner in this change.
  final Set<String> _loaderIn = <String>{};

  bool _fullScreenLoader() {
    if (shows(byKey('start-spinner')) ||
        shows(byKey('deferred-screen-loading'))) {
      return true;
    }
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    final area = screen.width * screen.height;
    for (final e in find.byType(CircularProgressIndicator).evaluate()) {
      var inButton = false;
      Size? box;
      e.visitAncestorElements((a) {
        final w = a.widget;
        if (w is ButtonStyleButton || w is InkWell || w is IconButton) {
          inButton = true;
          return false;
        }
        if (w is Center || w is Align) {
          final r = a.renderObject;
          if (r is RenderBox && r.hasSize) box = r.size;
          return false;
        }
        return true;
      });
      final b = box;
      if (!inButton && b != null && b.width * b.height >= 0.6 * area) {
        // G31 run 1: say WHICH screen shows the loader (the route picker's
        // own "finishing" overlay, Select ride's "Checking your area", ...).
        e.visitAncestorElements((a) {
          final name = a.widget.runtimeType.toString();
          const framework = {'PageView', 'ListView', 'GridView'};
          if (!framework.contains(name) &&
              (name.endsWith('Page') ||
                  name.endsWith('View') ||
                  name == 'SelectRide')) {
            _loaderIn.add(name);
            return false;
          }
          return true;
        });
        return true;
      }
    }
    return false;
  }

  void _report(
    String name,
    List<FrameTiming> frames,
    int mark,
    Map<String, Set<int>> before,
    Map<String, Set<int>> after,
    int blank,
    int loader,
    List<String> exceptions,
    List<(int, String)> expected, {
    required String? sameOwnerNewMap,
    required String owners,
  }) {
    double ms(Duration d) => d.inMicroseconds / 1000.0;
    var missed = 0;
    var worst = 0.0;
    for (final f in frames) {
      final build = f.buildDuration, raster = f.rasterDuration;
      if (build > _budget || raster > _budget) missed++;
      final w = ms(build) > ms(raster) ? ms(build) : ms(raster);
      if (w > worst) worst = w;
    }
    final ratio = frames.isEmpty ? 0.0 : missed / frames.length;
    final smooth =
        worst <= freezeMs &&
        (frames.length < minFramesForRatio || ratio <= missedLimit);

    final calls = rec.since(mark);
    final gets = calls
        .where((c) => c.method == 'GET' && !c.isBackground)
        .toList();
    final perPath = <String, int>{};
    for (final c in gets) {
      perPath[c.path] = (perPath[c.path] ?? 0) + 1;
    }
    // Only the screen change itself (its first [settleWindow]): a long
    // transition (driving to the pickup) has the app's normal polling.
    final settled = gets.isEmpty
        ? gets
        : gets
              .where((c) => c.at.difference(gets.first.at) < settleWindow)
              .toList();
    final repeated = <String>{};
    for (var i = 0; i < settled.length; i++) {
      for (var j = i + 1; j < settled.length; j++) {
        final a = settled[i], b = settled[j];
        if (a.label == b.label && b.at.difference(a.at) < repeatWindow) {
          repeated.add(a.label);
        }
      }
    }
    final recreated = <String>[
      for (final owner in before.keys)
        if (after.containsKey(owner) &&
            after[owner]!.intersection(before[owner]!).isEmpty)
          owner,
      if (_homeBaseline case final home?)
        if (after['home'] case final now?)
          if (now.intersection(home).isEmpty && !before.containsKey('home'))
            'home (Home came back with a new map)',
      ?sameOwnerNewMap,
    ];
    bool isExpected(RecordedCall c) =>
        expected.any((e) => c.status == e.$1 && c.path.contains(e.$2));

    final failed = <String>[
      for (final c in calls)
        if (c.failed && !isExpected(c)) '$c',
    ];
    final allowed = <String>[
      for (final c in calls)
        if (c.failed && isExpected(c)) '$c',
    ];
    final crashReports = <String>[
      for (final c in calls)
        if (c.isCrashReport) '$c',
    ];

    final smoothDetail =
        'frames=${frames.length} missed=$missed '
        '(${(ratio * 100).toStringAsFixed(0)}%) worst=${worst.toStringAsFixed(1)} ms '
        '[FAIL above $freezeMs ms or ${(missedLimit * 100).round()}% missed '
        'with >= $minFramesForRatio frames; $buildMode]';
    final reloadDetail =
        'GET reads=${gets.length} $perPath repeated<4s=${repeated.toList()}; '
        'maps before=${_ids(before)} after=${_ids(after)} map owner $owners '
        'recreated=$recreated; full-screen loader samples=$loader '
        '${_loaderIn.isEmpty ? '' : 'in=${_loaderIn.toList()} '}'
        'blank samples=$blank';
    final errorDetail =
        'calls=${calls.length} failed=$failed expected=$allowed '
        'exceptions=$exceptions crash reports=$crashReports';
    final reloadOk =
        recreated.isEmpty && loader == 0 && blank == 0 && repeated.isEmpty;
    final errorsOk =
        failed.isEmpty && exceptions.isEmpty && crashReports.isEmpty;

    void check(String kind, bool ok, String title, String detail) {
      final id = 'TRANSITION:$name:$kind';
      ok ? log.pass(id, title, detail) : log.fail(id, title, detail);
    }

    check('SMOOTH', smooth, 'screen change has no freeze', smoothDetail);
    check('RELOAD', reloadOk, 'screen change does not reload', reloadDetail);
    check('ERRORS', errorsOk, 'screen change has no error', errorDetail);
    rows.add(<String, Object?>{
      'name': name,
      'frames': frames.length,
      'missed': missed,
      'worstMs': double.parse(worst.toStringAsFixed(1)),
      'gets': gets.length,
      'repeatedReads': repeated.toList(),
      'recreatedMaps': recreated,
      'loaderSamples': loader,
      'blankSamples': blank,
      'failedCalls': failed,
      'exceptions': [...exceptions, ...crashReports],
      'smooth': smooth,
      'reload': !reloadOk,
      'errors': !errorsOk,
      'build': buildMode,
    });
  }

  static Map<String, int> _ids(Map<String, Set<int>> maps) => {
    for (final MapEntry(:key, :value) in maps.entries) key: value.length,
  };
}
