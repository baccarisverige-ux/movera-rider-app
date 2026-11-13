import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// One call the app made through its HTTP client: what and how it ended.
///
/// Only the method, the path, the query parameter NAMES and the status are
/// kept for the report: never a body, a header or a query value (bodies and
/// headers hold the phone number, the code and the session token).
class RecordedCall {
  RecordedCall({
    required this.at,
    required this.method,
    required this.path,
    required this.queryNames,
  });

  final DateTime at;
  final String method;
  final String path;
  final List<String> queryNames;

  /// The answer's status, or null while waiting / when the call threw.
  int? status;

  /// The error type when the call threw (no message: it may hold a URL).
  String? error;

  Duration? took;

  /// The zone the call named (`?zoneId=`), kept for the G17 check; a zone
  /// id is not personal data.
  String? zoneId;

  /// The decoded answer, only for [RecordingClient.kept] paths (in memory
  /// for the checks; never printed).
  Object? answer;

  bool get failed => error != null || (status != null && status! >= 400);

  /// Long-lived event streams and the app's own telemetry (log lines,
  /// crash reports) are not "page reads".
  bool get isBackground =>
      path.endsWith('/stream') ||
      path.endsWith('/events') ||
      path.startsWith('/api/v1/telemetry/');

  /// The app reported a crash to its own sink (HttpObservabilitySink).
  bool get isCrashReport =>
      method == 'POST' && path.startsWith('/api/v1/telemetry/crash');

  String get label =>
      '$method $path${queryNames.isEmpty ? '' : '?${queryNames.join('&')}'}';

  @override
  String toString() =>
      '$label -> ${error ?? status ?? 'pending'}'
      '${took == null ? '' : ' (${took!.inMilliseconds} ms)'}';
}

/// The app's own HTTP client, recording every call it makes (G27 re-reads
/// after Back, failed calls per screen change) and keeping the last JSON
/// answer of a few read-only resources for the checks to compare against.
///
/// G31 rider: a copy of the driver suite's client with the rider app's
/// paths in [keeps] and its telemetry as background calls.
class RecordingClient extends http.BaseClient {
  RecordingClient(this._inner, {required this.apiHost});

  final http.Client _inner;

  /// Only this host's calls carry the session token the checks re-use.
  final String apiHost;

  final List<RecordedCall> calls = <RecordedCall>[];

  /// Last decoded JSON answer per path, for these paths only.
  static const Set<String> kept = <String>{
    '/api/v1/rider/config',
    '/api/v1/rider/zones',
    '/api/v1/rider/trips/active',
    '/api/v1/rider/trips',
    '/api/v1/quotes',
    '/api/v1/trips',
    '/api/v1/locations/autocomplete',
  };

  /// Kept too: the trip itself and its sub-resources the checks compare
  /// (`/trips/{id}`, its call, PIN, rating and receipt answers).
  static bool keeps(String path) =>
      kept.contains(path) ||
      (path.startsWith('/api/v1/trips/') &&
          !path.endsWith('/stream') &&
          !path.endsWith('/events'));

  final Map<String, Object?> lastAnswer = <String, Object?>{};

  /// The session's `Authorization` header, in memory only (never logged),
  /// so a check can ask the server the same question itself.
  String? _authorization;

  String? get authorization => _authorization;

  int get length => calls.length;

  /// Calls made since [mark] (an earlier [length]).
  List<RecordedCall> since(int mark) => calls.sublist(mark);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final url = request.url;
    final call = RecordedCall(
      at: DateTime.now(),
      method: request.method,
      path: url.path,
      queryNames: url.queryParameters.keys.toList()..sort(),
    )..zoneId = url.queryParameters['zoneId'];
    calls.add(call);
    if (url.host == apiHost) {
      final auth =
          request.headers['Authorization'] ?? request.headers['authorization'];
      if (auth != null && auth.startsWith('Bearer ')) _authorization = auth;
    }
    final watch = Stopwatch()..start();
    http.StreamedResponse response;
    try {
      response = await _inner.send(request);
    } catch (error) {
      call
        ..error = error.runtimeType.toString()
        ..took = watch.elapsed;
      rethrow;
    }
    call
      ..status = response.statusCode
      ..took = watch.elapsed;
    final type = response.headers['content-type'] ?? '';
    final keep =
        url.host == apiHost &&
        keeps(url.path) &&
        type.contains('json') &&
        (response.contentLength ?? 0) < 1 << 20;
    if (!keep) return response;
    // Read the (small) JSON answer once and hand the app the same bytes.
    final bytes = await response.stream.toBytes();
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      call.answer = decoded;
      lastAnswer[url.path] = decoded;
    } catch (_) {
      // Not JSON after all: the app sees it as it came.
    }
    return http.StreamedResponse(
      Stream<List<int>>.value(bytes),
      response.statusCode,
      contentLength: bytes.length,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() => _inner.close();
}
