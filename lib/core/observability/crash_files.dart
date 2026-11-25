export 'package:movera_rider/core/observability/crash_files_io.dart'
    if (dart.library.js_interop) 'package:movera_rider/core/observability/crash_files_web.dart';

/// The small files the crash catcher keeps on the phone (contract v0.18.158
/// `contract.json#crashCatcher.runningMarker`): the running marker, the
/// breadcrumbs, the outbox of unsent reports, the last crash-report switch
/// and the native crash file the iOS / Android code writes. Every call is
/// synchronous so a marker or breadcrumb is on disk before a crash can
/// stop the app; a failure to read or write is never thrown.
abstract interface class CrashFiles {
  String? read(String name);
  void write(String name, String text);
  void delete(String name);
}

/// Kept in memory only (tests, and the web where no marker is kept).
class MemoryCrashFiles implements CrashFiles {
  final Map<String, String> files = {};

  @override
  String? read(String name) => files[name];

  @override
  void write(String name, String text) => files[name] = text;

  @override
  void delete(String name) => files.remove(name);
}

/// The file names the iOS / Android code writes too (keep them in step with
/// AppDelegate.swift and MainActivity.kt).
abstract final class CrashFileNames {
  static const running = 'movera_running.json';
  static const breadcrumbs = 'movera_breadcrumbs.json';
  static const outbox = 'movera_crash_outbox.json';
  static const settings = 'movera_crash_settings.json';
  static const native = 'movera_native_crash.json';
  static const device = 'movera_device.json';
}
