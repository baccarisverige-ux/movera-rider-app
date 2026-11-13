import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:movera_rider/app/bootstrap.dart';
import 'package:movera_rider/app/config/env.dart';

import 'check_log.dart';
import 'movera_api.dart';
import 'recording_client.dart';
import 'rider_steps.dart';

/// Central Stockholm (zone Z001) unless the run names another point; the
/// same default as MainActivityTest's mock position (the rider's pickup).
const double defaultLat = 59.3326;
const double defaultLng = 18.0649;

/// The drop-off the rider types on Where to (run argument
/// movera_tl_dropoff_query), ~0.8 km from the default pickup.
const String defaultDropoffQuery = 'Stureplan';

String? tlEnv(String name) {
  final value = Platform.environment[name]?.trim();
  return value == null || value.isEmpty ? null : value;
}

/// The real rider app on the phone (G31 rider), started the way
/// lib/main_staging.dart starts it (`bootstrap()`), with the test's
/// recording client as the app's HTTP client.
///
/// The rider app has no client parameter: `ApiClient` makes its own
/// `http.Client()` inside `AppScope.instance`, which `bootstrap()` builds
/// synchronously. [start] runs `bootstrap()` inside `http.runWithClient`,
/// so that `http.Client()` (the API's and the crash sink's) is [rec]. Its
/// first recorded call proves it ([clientInUse]); without it the RELOAD and
/// ERRORS checks are NOT CHECKED.
///
/// Nothing here may touch `AppScope.instance` before [start]: the first
/// touch builds the app's clients, and outside the zone they would not
/// record.
class RiderSession {
  RiderSession(this.tester, this.log)
    : base = _root(AppEnv.current.apiBaseUrl),
      rec = RecordingClient(
        http.Client(),
        apiHost: Uri.parse(AppEnv.current.apiBaseUrl).host,
      ) {
    riderApi = RiderApi(base);
  }

  static Uri _root(String url) {
    final u = Uri.parse(url);
    return Uri(scheme: u.scheme, host: u.host, port: u.port);
  }

  final WidgetTester tester;
  final CheckLog log;
  final Uri base;
  final RecordingClient rec;

  /// The rider's own session over HTTP, using the app's token (read from
  /// the recorded calls; never printed). The test asks the server what the
  /// app should show with it.
  late final RiderApi riderApi;

  final double lat =
      double.tryParse(tlEnv('MOVERA_TL_LAT') ?? '') ?? defaultLat;
  final double lng =
      double.tryParse(tlEnv('MOVERA_TL_LNG') ?? '') ?? defaultLng;
  final String dropoffQuery =
      tlEnv('MOVERA_TL_DROPOFF_QUERY') ?? defaultDropoffQuery;

  /// Flutter exceptions the app reported while the run went on (type only).
  final List<String> appExceptions = <String>[];

  FlutterExceptionHandler? _testOnError;
  ErrorCallback? _testPlatformOnError;
  bool _handlersSaved = false;

  /// The app's first call went through [rec].
  bool get clientInUse => rec.calls.isNotEmpty;

  Future<void> start() async {
    // bootstrap() replaces FlutterError.onError and PlatformDispatcher
    // .onError with the app's crash sink. flutter_test fails a test that
    // leaves them changed, so the test's own are kept and put back in
    // [restoreHandlers]; meanwhile the app's handler runs after a count.
    _testOnError = FlutterError.onError;
    _testPlatformOnError = PlatformDispatcher.instance.onError;
    _handlersSaved = true;
    await http.runWithClient(bootstrap, () => rec);
    final appOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      appExceptions.add(details.exception.runtimeType.toString());
      CheckLog.say(
        'STEP app exception ${details.exception.runtimeType} '
        '(${details.library ?? 'no library'})',
      );
      appOnError?.call(details);
    };
    await tester.pump();
  }

  /// Puts the test's error handlers back (always, in the test's finally).
  void restoreHandlers() {
    if (!_handlersSaved) return;
    FlutterError.onError = _testOnError;
    PlatformDispatcher.instance.onError = _testPlatformOnError;
    _handlersSaved = false;
  }

  /// Runs [body]; an exception is a failure text, not a crash of the run.
  Future<String?> guard(Future<String?> Function() body) async {
    try {
      return await body();
    } catch (error) {
      return 'stopped by ${error.runtimeType}: $error';
    }
  }

  Iterable<RecordedCall> calls(String path, {String? method, int from = 0}) =>
      rec
          .since(from)
          .where(
            (c) => c.path == path && (method == null || c.method == method),
          );

  /// Calls whose path matches [pattern] since [from].
  Iterable<RecordedCall> callsMatching(
    RegExp pattern, {
    String? method,
    int from = 0,
  }) => rec
      .since(from)
      .where(
        (c) =>
            pattern.hasMatch(c.path) && (method == null || c.method == method),
      );

  /// GET [path] with the app's own session, asked by the test itself.
  Future<(int, Object?)> ask(String path, [Map<String, String>? query]) async {
    if (rec.authorization == null) return (0, null);
    final answer = await riderApi.get(
      path,
      query: query,
      timeout: const Duration(seconds: 60),
    );
    return (answer.status, answer.body);
  }

  /// Waits until the app has a session token (after sign-in) and gives it
  /// to [riderApi]. False when none came in [timeout].
  Future<bool> adoptAppSession({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    await pumpUntil(tester, () => rec.authorization != null, timeout: timeout);
    final auth = rec.authorization;
    if (auth == null) return false;
    riderApi.token = auth;
    return true;
  }

  /// The app may refresh its token: the latest one is used.
  void refreshRiderToken() {
    final auth = rec.authorization;
    if (auth != null) riderApi.token = auth;
  }
}
