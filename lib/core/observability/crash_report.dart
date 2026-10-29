import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:movera_rider/core/observability/observability.dart';

/// The body of one `POST /telemetry/crashes` (contract v0.16.0 §11,
/// `contract.json#telemetry.crashReport`).
///
/// Owner 2026-10-29: "Add automatic and add this in term and condition":
/// reports go out on their own, there is no switch. Everything personal is
/// scrubbed here before it leaves the device (the server scrubs again).
abstract final class CrashReport {
  /// The server refuses a body over 16 KB (`TELEMETRY.maxBodyBytes`).
  static const maxBytes = 16 * 1024;

  /// `TelemetryCrash` limits: error 4000, stack 12000 characters.
  static const maxError = 4000;
  static const maxStack = 12000;

  static String _cut(String text, int max) =>
      text.length > max ? text.substring(0, max) : text;

  static const kindCrash = 'crash';
  static const kindError = 'error';

  /// The route name of the screen on top, kept by the navigator observer so
  /// a crash with no screen of its own still says where it happened.
  static String? currentScreen;

  /// `android`, `ios` or `web`; null on any other platform (the contract
  /// lists only these three).
  static String? platformName({bool isWeb = kIsWeb, TargetPlatform? platform}) {
    if (isWeb) return 'web';
    switch (platform ?? defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      default:
        return null;
    }
  }

  /// Splits a pubspec version (`1.4.2+17`) into the version and the build.
  static ({String version, String? build}) splitVersion(String raw) {
    final value = raw.trim();
    final plus = value.indexOf('+');
    if (plus == -1) return (version: value, build: null);
    final build = value.substring(plus + 1);
    return (
      version: value.substring(0, plus),
      build: build.isEmpty ? null : build,
    );
  }

  /// A screen or route name with no ids in it, at most 80 characters.
  static String? cleanScreen(Object? raw) {
    if (raw is! String) return null;
    var value = raw.split('?').first.trim();
    value = value.replaceAll(
      RegExp(r'(?=[0-9a-fA-F-]*\d)[0-9a-fA-F-]{8,}|\d+'),
      ':id',
    );
    value = value.replaceAll(RegExp(r'[^A-Za-z0-9_:./ -]'), '');
    value = Observability.scrubText(value).trim();
    if (value.isEmpty) return null;
    return value.length > 80 ? value.substring(0, 80) : value;
  }

  /// Same error at the same place: used to drop bursts of one crash.
  static String fingerprint(String kind, String error, String stack) {
    final firstFrame = stack
        .split('\n')
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => '');
    final head = error.length > 200 ? error.substring(0, 200) : error;
    return '$kind|$head|$firstFrame';
  }

  /// The scrubbed body, cut to fit [maxBytes]: the stack is shortened
  /// first, then the error text, then `extra` is left out.
  static Map<String, Object?> body({
    required Object error,
    required StackTrace stackTrace,
    Map<String, Object?> extra = const {},
    required String app,
    String? platform,
    String? appVersion,
    String? build,
    String? screen,
    String kind = kindCrash,
    required DateTime occurredAt,
  }) {
    final cleanExtra = Observability.sanitize({
      for (final entry in extra.entries)
        if (entry.key != 'screen' && entry.key != 'kind')
          entry.key: entry.value,
    });
    var errorText = _cut(
      Observability.scrubText(_cut(error.toString(), maxError)),
      maxError,
    );
    var stack = _cut(
      Observability.scrubText(_cut(stackTrace.toString(), maxStack)),
      maxStack,
    );
    appVersion = appVersion == null ? null : _cut(appVersion, 40);
    build = build == null ? null : _cut(build, 40);
    Map<String, Object?> build0() => {
      'error': errorText,
      'stack': stack,
      'extra': cleanExtra,
      'app': app,
      if (platform != null) 'platform': platform,
      if (appVersion != null && appVersion.isNotEmpty) 'appVersion': appVersion,
      if (build != null && build.isNotEmpty) 'build': build,
      if (cleanScreen(screen) case final s?) 'screen': s,
      'kind': kind == kindError ? kindError : kindCrash,
      'occurredAt': occurredAt.toUtc().toIso8601String(),
    };
    var result = build0();
    int size() => utf8.encode(jsonEncode(result)).length;
    while (size() > maxBytes && stack.isNotEmpty) {
      stack = stack.substring(0, stack.length ~/ 2);
      result = build0();
    }
    while (size() > maxBytes && errorText.length > 64) {
      errorText = errorText.substring(0, errorText.length ~/ 2);
      result = build0();
    }
    if (size() > maxBytes) {
      cleanExtra.clear();
      result = build0();
    }
    return result;
  }
}
