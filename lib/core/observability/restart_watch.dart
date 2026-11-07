import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:movera_rider/core/observability/crash_report.dart';

export 'package:movera_rider/core/observability/restart_watch_io.dart'
    if (dart.library.js_interop) 'package:movera_rider/core/observability/restart_watch_web.dart';

/// Where the restart marker is kept: the page's `localStorage` on the web.
abstract interface class RestartMarkerStore {
  String? read();
  void write(String value);
}

/// Sends one diagnostic line through the app's crash report channel.
typedef RestartReport = void Function(String message);

/// Restart diagnostic (owner 2026-11-07, "5. Mouchard redémarrage"; Rules
/// plan/AUDIT-TRIP-LIFECYCLE-2026-11-07.md). The installed web app on an
/// iPhone sometimes starts again from zero during a trip, with no reload in
/// the code. The leading guess is that iOS kills the page for memory; this
/// gives the proof.
///
/// Every [beatEvery], on each screen change and on each trip stage change
/// a small JSON marker is written: session id, start time, last beat, last
/// screen (route name) and trip stage, whether the page was visible, when
/// it went to the background, and a `clean` flag set on `pagehide`. No
/// name, number or coordinate is kept.
///
/// On the next start, a marker that was not clean and whose last beat is
/// less than [recent] old means the page died: one `error` report says so,
/// marked on screen or background (owner decision Q5, 2026-11-07, "Report
/// background too": iOS kills a page switched away from with no pagehide,
/// finding D6), with the last screen and, for background, the time away.
/// A lost WebGL context is reported once per session the same way.
class RestartWatch {
  RestartWatch({
    required this.store,
    required this.report,
    this.screen,
    DateTime Function()? clock,
    String? sessionId,
    this.recent = const Duration(minutes: 10),
  }) : _clock = clock ?? DateTime.now,
       sessionId = sessionId ?? _newId();

  static const storageKey = 'movera.restart_watch.v1';
  static const beatEvery = Duration(seconds: 2);

  /// The running watch (live web builds only); null elsewhere.
  static RestartWatch? instance;

  /// The ride status the rider is on, or null with no trip.
  static String? tripStage;

  /// A screen change: the marker is written at once.
  static void touch() {
    try {
      instance?.beat();
    } catch (_) {
      // Diagnostic only: storage or the browser may refuse; never break the app.
    }
  }

  /// A trip stage change: kept and written at once.
  static void noteStage(String? stage) {
    if (stage == tripStage) return;
    tripStage = stage;
    touch();
  }

  final RestartMarkerStore store;
  final RestartReport report;

  /// The screen on top (the route name); [CrashReport.currentScreen] when
  /// not given.
  final String? Function()? screen;
  final Duration recent;
  final String sessionId;
  final DateTime Function() _clock;

  /// Runs after each beat (the web binding watches new canvases here).
  void Function()? onBeat;

  late DateTime _startedAt;
  bool _visible = true;
  DateTime? _hiddenAt;
  bool _clean = false;
  bool _lostReported = false;
  Timer? _timer;

  static String _newId() {
    final random = Random();
    return List.generate(8, (_) => random.nextInt(16).toRadixString(16)).join();
  }

  String? _screen() =>
      CrashReport.cleanScreen((screen ?? () => CrashReport.currentScreen)());

  String? _stage() => CrashReport.cleanScreen(tripStage);

  /// Checks the marker the last session left, then starts beating.
  void start({required bool visible, bool periodic = true}) {
    _startedAt = _clock();
    _visible = visible;
    _hiddenAt = visible ? null : _startedAt;
    String? previous;
    try {
      previous = store.read();
    } catch (_) {
      // Diagnostic only: storage or the browser may refuse; never break the app.
    }
    final message = unexpectedRestart(previous, _startedAt, recent: recent);
    if (message != null) _send(message);
    beat();
    if (periodic) _timer = Timer.periodic(beatEvery, (_) => beat());
  }

  /// Writes the marker now.
  void beat() {
    final now = _clock();
    final marker = <String, Object?>{
      'v': 1,
      'id': sessionId,
      'start': _startedAt.millisecondsSinceEpoch,
      'beat': now.millisecondsSinceEpoch,
      'screen': _screen(),
      'stage': _stage(),
      'visible': _visible,
      'clean': _clean,
      'hidden': ?_hiddenAt?.millisecondsSinceEpoch,
    };
    try {
      store.write(jsonEncode(marker));
    } catch (_) {
      // Diagnostic only: storage or the browser may refuse; never break the app.
    }
    try {
      onBeat?.call();
    } catch (_) {
      // Diagnostic only: storage or the browser may refuse; never break the app.
    }
  }

  /// `visibilitychange`.
  void setVisible(bool visible) {
    if (!visible && _visible) _hiddenAt = _clock();
    if (visible) _hiddenAt = null;
    _visible = visible;
    beat();
  }

  /// `pagehide`: the page is closed or reloaded on purpose.
  void pageHide() {
    _clean = true;
    beat();
  }

  /// `pageshow` from the back/forward cache: the same session goes on.
  void pageShow() {
    _clean = false;
    _visible = true;
    _hiddenAt = null;
    beat();
  }

  /// `webglcontextlost` on one of the page's canvases: reported once.
  void contextLost() {
    if (_lostReported) return;
    _lostReported = true;
    final uptime = _clock().difference(_startedAt).inSeconds;
    _send(
      'webgl context lost: last screen ${_describe(_screen(), _stage())}, '
      'uptime $uptime s',
    );
    beat();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void _send(String message) {
    try {
      report(message);
    } catch (_) {
      // Diagnostic only: storage or the browser may refuse; never break the app.
    }
  }

  static String _describe(String? screen, String? stage) {
    final name = screen ?? 'unknown';
    return stage == null ? name : '$name (trip stage $stage)';
  }

  /// The report for the marker [previous] left at [now], or null when that
  /// session ended cleanly, is too old or cannot be read.
  static String? unexpectedRestart(
    String? previous,
    DateTime now, {
    Duration recent = const Duration(minutes: 10),
  }) {
    if (previous == null || previous.isEmpty) return null;
    Object? decoded;
    try {
      decoded = jsonDecode(previous);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    final beat = decoded['beat'];
    final start = decoded['start'];
    if (beat is! int || start is! int) return null;
    if (decoded['clean'] == true) return null;
    final since = now.millisecondsSinceEpoch - beat;
    if (since < 0 || since >= recent.inMilliseconds) return null;
    final screen = _describe(
      CrashReport.cleanScreen(decoded['screen']),
      CrashReport.cleanScreen(decoded['stage']),
    );
    final uptime = ((beat - start) / 1000).round();
    final after = '${(since / 1000).round()} s after last beat';
    if (decoded['visible'] == true) {
      return 'unexpected restart (on screen): last screen $screen, $after, '
          'uptime $uptime s';
    }
    final hidden = decoded['hidden'];
    final hiddenAt = hidden is int && hidden <= beat ? hidden : beat;
    final away = ((now.millisecondsSinceEpoch - hiddenAt) / 1000).round();
    return 'unexpected restart (background): last screen $screen, '
        'away $away s, $after, uptime $uptime s';
  }
}
