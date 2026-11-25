import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:movera_rider/core/observability/crash_breadcrumbs.dart';
import 'package:movera_rider/core/observability/crash_files.dart';
import 'package:movera_rider/core/observability/crash_report.dart';

/// One report the catcher hands to the app's crash sink.
class CrashEvent {
  const CrashEvent({
    required this.kind,
    required this.message,
    this.stack = '',
    this.nativeReason,
    this.freezeMs,
    this.screen,
    this.breadcrumbs,
    this.extra = const {},
  });

  final String kind;
  final String message;
  final String stack;
  final Map<String, String>? nativeReason;
  final int? freezeMs;
  final String? screen;

  /// The breadcrumbs of the run the report is about (a native crash: the run
  /// that ended); null = the current ones.
  final List<Map<String, Object?>>? breadcrumbs;
  final Map<String, Object?> extra;
}

/// Reports that could not be sent (offline, 5xx, 429) wait in a file of at
/// most [max] and go again later and at the next launch, oldest first
/// (contract v0.18.158 `contract.json#crashCatcher.outbox`).
class CrashOutbox {
  CrashOutbox(this._files);

  static const max = 20;
  final CrashFiles _files;
  int _next = 0;

  List<Map<String, Object?>> _all() {
    try {
      final raw = _files.read(CrashFileNames.outbox);
      if (raw == null) return [];
      final list = jsonDecode(raw);
      if (list is! List) return [];
      return [
        for (final item in list)
          if (item is Map && item['body'] is Map)
            {
              'id': '${item['id']}',
              'body': Map<String, Object?>.from(item['body'] as Map),
            },
      ];
    } catch (_) {
      return [];
    }
  }

  void _save(List<Map<String, Object?>> items) {
    try {
      _files.write(CrashFileNames.outbox, jsonEncode(items));
    } catch (_) {
      // Never shown and never fatal: a crash report must not crash the app.
    }
  }

  /// Keeps [body]; returns its id.
  String add(Map<String, Object?> body) {
    final items = _all();
    final id = '${DateTime.now().microsecondsSinceEpoch}-${_next++}';
    items.add({'id': id, 'body': body});
    while (items.length > max) {
      items.removeAt(0);
    }
    _save(items);
    return id;
  }

  void remove(String id) {
    final items = _all();
    final before = items.length;
    items.removeWhere((item) => item['id'] == id);
    if (items.length != before) _save(items);
  }

  /// The kept reports (id, body), oldest first.
  List<({String id, Map<String, Object?> body})> pending() => [
    for (final item in _all())
      (id: item['id']! as String, body: item['body']! as Map<String, Object?>),
  ];
}

/// Every kind of crash reaches the admin (owner 2026-11-24 "Add to admin all
/// kind of crash"; contract v0.18.158 `contract.json#crashCatcher`):
///
/// * a running marker written at start and on resume, deleted on pause /
///   hide / detach: still there at the next launch = the app did not end
///   cleanly, so one `native_crash` report goes out with the native reason
///   the iOS / Android handlers wrote (if any), the last screen and the
///   breadcrumbs of that run;
/// * a freeze watch: no timer tick for [freezeLimit] or more while the app
///   is in front = one `freeze` report when the screen moves again;
/// * the last crash-report switch the zone's document gave (crashReports.on),
///   kept so a crash before the document is read follows it.
class CrashCatcher with WidgetsBindingObserver {
  CrashCatcher({
    required CrashFiles files,
    required this.send,
    CrashBreadcrumbs? breadcrumbs,
    DateTime Function()? clock,
    this.freezeLimit = const Duration(seconds: 5),
    this.tick = const Duration(seconds: 1),
    this.appVersion,
    this.build,
    this.markerSupported = true,
  }) : _files = files,
       _clock = clock ?? DateTime.now,
       crumbs = breadcrumbs ?? CrashBreadcrumbs.instance,
       outbox = CrashOutbox(files);

  /// The running app's catcher (null in tests and before start).
  static CrashCatcher? instance;

  final CrashFiles _files;
  final DateTime Function() _clock;
  final void Function(CrashEvent event) send;
  final CrashBreadcrumbs crumbs;
  final CrashOutbox outbox;
  final Duration freezeLimit;
  final Duration tick;
  final String? appVersion;
  final String? build;
  final bool markerSupported;

  Timer? _ticker;
  DateTime? _lastTick;
  bool _foreground = true;
  String? _device;
  bool _deviceRead = false;

  /// The device model and OS line the native code wrote at launch.
  ({String? model, String? os}) get device {
    if (!_deviceRead) {
      final raw = _files.read(CrashFileNames.device);
      if (raw != null) {
        _device = raw;
        _deviceRead = true;
      }
    }
    try {
      final map = _device == null ? null : jsonDecode(_device!);
      if (map is Map) {
        return (model: _cut(map['model'], 80), os: _cut(map['os'], 60));
      }
    } catch (_) {
      // Never shown and never fatal: a crash report must not crash the app.
    }
    return (model: null, os: null);
  }

  static String? _cut(Object? value, int max) {
    if (value is! String || value.trim().isEmpty) return null;
    final text = value.trim();
    return text.length > max ? text.substring(0, max) : text;
  }

  /// The zone's switch (contract `crashReports.on`), kept on the phone.
  bool get reportingOn {
    try {
      final raw = _files.read(CrashFileNames.settings);
      if (raw == null) return true;
      final map = jsonDecode(raw);
      return !(map is Map && map['on'] == false);
    } catch (_) {
      return true;
    }
  }

  set reportingOn(bool on) {
    _files.write(CrashFileNames.settings, jsonEncode({'on': on}));
    CrashReport.reportingEnabled = on;
  }

  /// Reads what the last run left, reports an unclean end, writes the new
  /// marker and starts the freeze watch.
  void start() {
    CrashReport.reportingEnabled = reportingOn;
    if (markerSupported) {
      _reportLastRun();
      _writeMarker();
      crumbs.clear();
      crumbs.onChange = _saveCrumbs;
    }
    _lastTick = _clock();
    _ticker?.cancel();
    _ticker = Timer.periodic(tick, (_) => checkFreeze());
    try {
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {
      // Never shown and never fatal: a crash report must not crash the app.
    }
  }

  void stop() {
    _ticker?.cancel();
    _ticker = null;
    crumbs.onChange = null;
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {
      // Never shown and never fatal: a crash report must not crash the app.
    }
  }

  void _reportLastRun() {
    final marker = _files.read(CrashFileNames.running);
    final native = _files.read(CrashFileNames.native);
    final lastCrumbs = _files.read(CrashFileNames.breadcrumbs);
    if (marker == null && native == null) return;
    Map<String, Object?> markerMap = const {};
    Map<String, Object?> nativeMap = const {};
    List<Map<String, Object?>> crumbsList = const [];
    try {
      final m = marker == null ? null : jsonDecode(marker);
      if (m is Map) markerMap = Map<String, Object?>.from(m);
    } catch (_) {
      // Never shown and never fatal: a crash report must not crash the app.
    }
    try {
      final n = native == null ? null : jsonDecode(native);
      if (n is Map) nativeMap = Map<String, Object?>.from(n);
    } catch (_) {
      // Never shown and never fatal: a crash report must not crash the app.
    }
    try {
      final c = lastCrumbs == null ? null : jsonDecode(lastCrumbs);
      if (c is List) {
        crumbsList = [
          for (final item in c)
            if (CrashBreadcrumb.fromJson(item) case final crumb?)
              crumb.toJson(),
        ];
      }
    } catch (_) {
      // Never shown and never fatal: a crash report must not crash the app.
    }
    String? lastScreen;
    for (final item in crumbsList.reversed) {
      if (item['type'] == 'route') {
        lastScreen = item['message'] as String?;
        break;
      }
    }
    final name = _cut(nativeMap['name'], 200);
    final reason = _cut(nativeMap['reason'], 1000);
    final message = name != null
        ? (reason != null ? '$name: $reason' : name)
        : 'App ended without a clean exit (last screen ${lastScreen ?? 'unknown'})';
    send(
      CrashEvent(
        kind: CrashReport.kindNativeCrash,
        message: message,
        stack: nativeMap['stack'] is String
            ? nativeMap['stack']! as String
            : '',
        nativeReason: name == null ? null : {'name': name, 'reason': ?reason},
        screen: lastScreen,
        breadcrumbs: crumbsList,
        extra: {
          if (markerMap['appVersion'] is String)
            'endedAppVersion': markerMap['appVersion'],
          if (markerMap['build'] is String) 'endedBuild': markerMap['build'],
        },
      ),
    );
    _files.delete(CrashFileNames.native);
    _files.delete(CrashFileNames.running);
  }

  void _writeMarker() {
    if (!markerSupported) return;
    _files.write(
      CrashFileNames.running,
      jsonEncode({
        'startedAt': _clock().toUtc().toIso8601String(),
        'appVersion': ?appVersion,
        'build': ?build,
      }),
    );
  }

  void _saveCrumbs() {
    try {
      _files.write(CrashFileNames.breadcrumbs, jsonEncode(crumbs.toJson()));
    } catch (_) {
      // Never shown and never fatal: a crash report must not crash the app.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => lifecycle(state);

  /// Resumed: in front again (marker back). Paused / hidden / detached:
  /// a clean way out (marker gone). Inactive changes nothing.
  void lifecycle(AppLifecycleState state) {
    crumbs.add('lifecycle', state.name);
    switch (state) {
      case AppLifecycleState.resumed:
        _foreground = true;
        _lastTick = _clock();
        _writeMarker();
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _foreground = false;
        if (markerSupported) _files.delete(CrashFileNames.running);
      case AppLifecycleState.inactive:
        break;
    }
  }

  /// One tick of the freeze watch (the timer calls it; tests call it).
  void checkFreeze() {
    final now = _clock();
    final last = _lastTick;
    _lastTick = now;
    if (last == null || !_foreground) return;
    final gap = now.difference(last) - tick;
    if (gap < freezeLimit) return;
    final screen = CrashReport.currentScreen ?? crumbs.lastScreen;
    final seconds = (gap.inMilliseconds / 1000).round();
    send(
      CrashEvent(
        kind: CrashReport.kindFreeze,
        message:
            'The screen froze for $seconds s (screen ${screen ?? 'unknown'})',
        freezeMs: gap.inMilliseconds,
        screen: screen,
      ),
    );
  }

  /// The fields every report of this run carries (device, OS, breadcrumbs).
  Map<String, Object?> context() {
    final d = device;
    return {
      'deviceModel': ?d.model,
      'osVersion': ?(d.os ?? fallbackOsVersion()),
      'breadcrumbs': crumbs.toJson(),
    };
  }
}
