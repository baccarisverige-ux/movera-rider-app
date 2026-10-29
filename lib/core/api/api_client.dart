import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/api/idempotency.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/auth/token_store.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/core/utils/request_id.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/core/contracts/server_clock.dart';

class ApiClient {
  /// `X-Api-Version` on every request: `contract.json#headers` (v0.5).
  static const apiVersion = '0.5';

  ApiClient({
    http.Client? client,
    AppEnv? env,
    TokenStore? tokens,
    Future<void> Function()? onSessionExpired,
    Duration? requestTimeout,
  }) : _env = env ?? AppEnv.current,
       _client = client ?? _defaultClient(env ?? AppEnv.current),
       _tokens = tokens,
       _onSessionExpired = onSessionExpired,
       requestTimeout =
           requestTimeout ??
           ((env ?? AppEnv.current).allowsMockTransport
               ? mockTransportTimeout
               : liveServerTimeout);

  /// How long one request to the in-process mock may take (demo, dev, test).
  static const mockTransportTimeout = Duration(seconds: 15);

  /// How long one request to movera-server may take on the contract wire.
  /// The live test week runs on a small instance that sleeps when idle and
  /// answers its first request after it wakes in 30-50 s; a 15 s limit
  /// turned that wake into "Couldn't reach Movera" on every screen.
  static const liveServerTimeout = Duration(seconds: 30);

  static http.Client _defaultClient(AppEnv env) {
    return env.allowsMockTransport
        ? InProcessMockClient(persistSafety: true, persistRides: true)
        : http.Client();
  }

  bool get usesMockTransport => _client is InProcessMockClient;

  /// Whether the booking calls (quotes, trips, cancel, end-early, rating,
  /// the trip lists) use the contract wire (openapi.yaml, v0.5): true in
  /// staging and production, which talk to movera-server only. The demo,
  /// dev and test builds keep the in-process mock's older dialect
  /// (`rideType`, `{quote}`, `{ride}`), which their tests are written to.
  bool get contractWire => !_env.allowsMockTransport;

  /// The path of trip [tripId] (and its command [segment]): contract
  /// `/trips/{tripId}` on the contract wire; the mock serves the older
  /// `/rides/{id}` (movera-server keeps that alias only for read and cancel).
  String tripPath(String tripId, [String? segment]) {
    final base = contractWire ? '/api/v1/trips' : '/api/v1/rides';
    final id = contractWire ? Uri.encodeComponent(tripId) : tripId;
    return segment == null ? '$base/$id' : '$base/$id/$segment';
  }

  final http.Client _client;
  final AppEnv _env;
  final TokenStore? _tokens;
  final Future<void> Function()? _onSessionExpired;
  Future<_Refresh>? _refreshInFlight;
  String? _expiredAccess;

  /// The limit for one request (a GET is tried twice on a timeout).
  final Duration requestTimeout;
  Duration get _timeout => requestTimeout;

  /// Contract v0.15.0 `auth.slowStart.waitSeconds` (owner 2026-10-29,
  /// decision 1): a sleeping server answers its first request after about
  /// 50 s, so the sign-in calls (and the waiting list) wait up to 60 s.
  static const signInTimeout = Duration(seconds: 60);

  static const _slowStartPaths = {
    '/api/v1/auth/otp/request',
    '/api/v1/auth/otp/verify',
    '/api/v1/auth/provider',
    '/api/v1/auth/waitlist',
  };

  /// Sign-in calls: their 401 means wrong credentials, never an expired
  /// session, whatever token the request happened to carry.
  static const _signInPaths = {
    '/api/v1/auth/otp/request',
    '/api/v1/auth/otp/verify',
    '/api/v1/auth/provider',
  };

  Future<Map<String, dynamic>> get(String path) => _send('GET', path);

  /// A Server-Sent Events GET (contract §4, e.g. `/rider/config/stream`):
  /// the stream's lines, with the session's token and `Last-Event-ID`. An
  /// answer of 400 or more is an [ApiError]; the caller reconnects.
  Future<Stream<String>> openEventStream(
    String path, {
    String? lastEventId,
  }) async {
    final requestId = newRequestId();
    final access = await _tokens?.readAccess();
    final request = http.Request('GET', Uri.parse('${_env.apiBaseUrl}$path'))
      ..headers.addAll({
        'Accept': 'text/event-stream',
        'X-Request-Id': requestId,
        'X-Api-Version': apiVersion,
        if (access != null) 'Authorization': 'Bearer $access',
        if (lastEventId != null) 'Last-Event-ID': lastEventId,
      });
    final response = await _client.send(request).timeout(_timeout);
    if (response.statusCode >= 400) {
      await response.stream.drain<void>();
      throw ApiError(
        code: 'HTTP_${response.statusCode}',
        message: 'The event stream was refused.',
        requestId: requestId,
        statusCode: response.statusCode,
      );
    }
    return response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());
  }

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
    String? idempotencyKey,
  }) {
    return _send('POST', path, body: body, idempotencyKey: idempotencyKey);
  }

  Future<Map<String, dynamic>> patch(
    String path, {
    Map<String, dynamic>? body,
    String? idempotencyKey,
  }) {
    return _send('PATCH', path, body: body, idempotencyKey: idempotencyKey);
  }

  Future<Map<String, dynamic>> delete(
    String path, {
    Map<String, dynamic>? body,
    String? idempotencyKey,
  }) {
    return _send('DELETE', path, body: body, idempotencyKey: idempotencyKey);
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? idempotencyKey,
  }) async {
    final requestId = newRequestId();
    final uri = Uri.parse('${_env.apiBaseUrl}$path');
    try {
      final access = await _tokens?.readAccess();
      final headers = <String, String>{
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'X-Request-Id': requestId,
        'X-Api-Version': apiVersion,
        if (access != null) 'Authorization': 'Bearer $access',
        // contract.json#headers: an Idempotency-Key on every mutation. A
        // caller that names none (a quote, a sign-out) gets one of its own
        // on the contract wire; movera-server refuses a change without it.
        if ((idempotencyKey ??
                (contractWire && method != 'GET'
                    ? newIdempotencyKey(method.toLowerCase())
                    : null))
            case final key?)
          'Idempotency-Key': key,
      };
      var response = await _request(
        method,
        uri,
        headers,
        body,
        timeout: _slowStartPaths.contains(path) ? signInTimeout : null,
      );
      if (response.statusCode == 401 &&
          access?.isNotEmpty == true &&
          !_signInPaths.contains(path)) {
        // An OTP rejection is not an expired session. Only requests that
        // carried an access token enter the refresh/retry path. rider-6: a
        // sign-in call can carry an earlier session's token (web keeps it in
        // sessionStorage across a reload), so its 401 is still a wrong code.
        final refresh = await _refreshAccess(access!);
        final replacement = refresh.access;
        if (refresh.unavailable) {
          // Offline, timed out or a server fault: the refresh token may still
          // be good, so the rider stays signed in and the caller sees an
          // ordinary network error it can retry.
          throw ApiError(
            code: 'NETWORK',
            message: L10n.current.apiUnreachable,
            requestId: requestId,
          );
        }
        if (replacement != null) {
          response = await _request(method, uri, {
            ...headers,
            'Authorization': 'Bearer $replacement',
          }, body);
        }
        if (replacement == null || response.statusCode == 401) {
          await _expireSession(
            replacement ?? access,
            cause: replacement == null ? refresh.cause : 'retry_401',
          );
        }
      }
      // rider-r4-32: how far this device's clock is from the server's.
      ServerClock.observeDateHeader(response.headers['date']);
      AppLog.info(
        'api.$method',
        extra: {
          'path': path,
          'requestId': requestId,
          'status': response.statusCode,
        },
      );
      if (response.statusCode >= 400) {
        throw _errorFromResponse(response, requestId);
      }
      if (response.body.isEmpty) return {'requestId': requestId};
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
      return {'data': decoded, 'requestId': requestId};
    } on TimeoutException {
      AppLog.error(
        'api.timeout',
        extra: {'path': path, 'requestId': requestId},
      );
      throw ApiError(
        code: 'TIMEOUT',
        message: 'Request timed out',
        requestId: requestId,
      );
    }
  }

  Future<http.Response> _request(
    String method,
    Uri uri,
    Map<String, String> headers,
    Map<String, dynamic>? body, {
    Duration? timeout,
  }) async {
    if (method == 'GET') {
      return _getWithRetry(uri, headers);
    } else if (method == 'DELETE') {
      return _client
          .send(http.Request('DELETE', uri)..headers.addAll(headers))
          .then(http.Response.fromStream)
          .timeout(_timeout);
    } else {
      final request = http.Request(method, uri)
        ..headers.addAll(headers)
        ..body = jsonEncode(body ?? {});
      return _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(timeout ?? _timeout);
    }
  }

  Future<_Refresh> _refreshAccess(String failedAccess) async {
    final active = _refreshInFlight;
    if (active != null) return active;
    final pending = _performRefresh(failedAccess);
    _refreshInFlight = pending;
    try {
      return await pending;
    } finally {
      _refreshInFlight = null;
    }
  }

  /// Only a definitive answer from the refresh endpoint ends the session.
  /// Anything that says nothing about the token itself (no network, timeout,
  /// 5xx, 429, an unreadable 200) keeps the tokens for a later retry.
  Future<_Refresh> _performRefresh(String failedAccess) async {
    final current = await _tokens?.readAccess();
    if (current != null && current != failedAccess) {
      return _Refresh.refreshed(current);
    }
    final refresh = await _tokens?.readRefresh();
    if (refresh == null || refresh.isEmpty) {
      return const _Refresh.rejected('no_refresh_token');
    }
    try {
      final response = await _client
          .post(
            Uri.parse('${_env.apiBaseUrl}/api/v1/auth/refresh'),
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'refreshToken': refresh}),
          )
          .timeout(_timeout);
      final status = response.statusCode;
      if (status == 400 || status == 401 || status == 403) {
        return _Refresh.rejected('refresh_$status');
      }
      if (status != 200) return const _Refresh.unavailable();
      final payload = jsonDecode(response.body);
      if (payload is! Map<String, dynamic>) return const _Refresh.unavailable();
      final access = payload['accessToken'];
      final nextRefresh = payload['refreshToken'];
      if (access is! String ||
          access.isEmpty ||
          nextRefresh is! String ||
          nextRefresh.isEmpty) {
        return const _Refresh.unavailable();
      }
      await _tokens?.save(access: access, refresh: nextRefresh);
      return _Refresh.refreshed(access);
    } catch (error) {
      AppLog.warning(
        'api.refresh_unavailable',
        extra: {'error': error.runtimeType.toString()},
      );
      return const _Refresh.unavailable();
    }
  }

  /// Runs once per rejected access token, so a burst of concurrent 401s
  /// does not clear the session and open Sign in several times.
  Future<void> _expireSession(
    String failedAccess, {
    required String? cause,
  }) async {
    if (_expiredAccess == failedAccess) return;
    _expiredAccess = failedAccess;
    // Why the rider was signed out (never the tokens), so a real expiry can
    // be told apart from a reload that only lost the session.
    AppLog.warning(
      'auth.session_expired',
      extra: {'cause': cause ?? 'unknown'},
    );
    await _tokens?.clear();
    await _onSessionExpired?.call();
  }

  ApiError _errorFromResponse(http.Response response, String requestId) {
    String code = 'HTTP_${response.statusCode}';
    String message = 'Request failed';
    String? reason;
    Map<String, dynamic>? projection;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final rawCode = decoded['code'] ?? decoded['error'];
        final rawMessage = decoded['message'];
        final rawReason = decoded['reason'];
        if (rawCode is String && rawCode.trim().isNotEmpty) {
          code = rawCode.trim();
        }
        if (rawMessage is String && rawMessage.trim().isNotEmpty) {
          message = rawMessage.trim();
        }
        if (rawReason is String && rawReason.trim().isNotEmpty) {
          reason = rawReason.trim();
        }
        // Contract errors shape: a 409 carries the current resource; the
        // pre-v0.3 mock also echoed it as `ride`.
        final rawProjection = decoded['projection'] ?? decoded['ride'];
        if (rawProjection is Map) {
          projection = Map<String, dynamic>.from(rawProjection);
        }
      }
    } catch (_) {
      // Non-JSON error bodies still retain the HTTP status and request id.
    }
    final retrySeconds = int.tryParse(response.headers['retry-after'] ?? '');
    return ApiError(
      code: code,
      message: message,
      requestId: requestId,
      statusCode: response.statusCode,
      retryAfter: retrySeconds == null ? null : Duration(seconds: retrySeconds),
      reason: reason,
      projection: projection,
    );
  }

  Future<http.Response> _getWithRetry(
    Uri uri,
    Map<String, String> headers,
  ) async {
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        return await _client.get(uri, headers: headers).timeout(_timeout);
      } on TimeoutException catch (error) {
        lastError = error;
      }
    }
    throw lastError ?? TimeoutException('GET retry failed');
  }
}

class _Refresh {
  const _Refresh.refreshed(String this.access)
    : unavailable = false,
      cause = null;
  const _Refresh.rejected(String this.cause)
    : access = null,
      unavailable = false;
  const _Refresh.unavailable()
    : access = null,
      unavailable = true,
      cause = null;

  final String? access;

  /// Why the refresh was refused (`refresh_401`, `no_refresh_token`, ...).
  final String? cause;

  /// The refresh endpoint could not answer; the tokens are kept.
  final bool unavailable;
}
