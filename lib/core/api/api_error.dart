class ApiError implements Exception {
  const ApiError({
    required this.code,
    required this.message,
    this.requestId,
    this.statusCode,
    this.retryAfter,
    this.reason,
    this.projection,
    this.details,
  });

  /// The contract error code (`contract.json#errors.codes`, lower case:
  /// `not_found`, `invalid_request`, `version_mismatch`, …), or a client
  /// code for failures that never reached a server (`NETWORK`, `TIMEOUT`).
  final String code;
  final String message;
  final String? requestId;
  final int? statusCode;
  final Duration? retryAfter;

  /// The server's more specific reason beside [code], when it sends one
  /// (`otp_expired`, `pickup_locked`, …). Not a contract field: screens
  /// fall back to [code] without it.
  final String? reason;

  /// The current resource a 409 carries (contract errors shape: always
  /// present for `version_mismatch` and `invalid_transition`).
  final Map<String, dynamic>? projection;

  /// The contract's `details` lines, when the server sends them (v0.18.7:
  /// `pickup_move_too_far` says `maxMeters=200`, `meters=…`).
  final List<String>? details;

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isAuthenticationFailure => isUnauthorized || isForbidden;

  /// `409 version_mismatch` (contract §1 Concurrency): the trip changed
  /// since the caller last read it. Nothing was applied; read it again.
  bool get isVersionMismatch => statusCode == 409 && code == 'version_mismatch';

  /// [reason] when the server sent one, else [code], in lower case: what
  /// screens match on (R-O4: the contract's codes are lower case).
  String get detail => (reason ?? code).trim().toLowerCase();

  bool get isRetryable =>
      statusCode == 408 ||
      statusCode == 429 ||
      (statusCode != null && statusCode! >= 500) ||
      code == 'TIMEOUT' ||
      code == 'NETWORK';

  @override
  String toString() => 'ApiError($code, $message, $requestId)';
}
