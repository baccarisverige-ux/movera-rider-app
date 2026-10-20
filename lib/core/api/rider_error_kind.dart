import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:movera_rider/core/api/api_error.dart';

/// What kind of failure a rider action hit, as far as the app can tell
/// without backend-specific reasons.
///
/// Screens turn this into words that also say what state the rider is left
/// in (still booked, not charged, ...). Specific reasons such as "too late to
/// cancel for free" come from backend error codes once they are defined; until
/// then they fall under [refused].
enum RiderErrorKind {
  /// The request may never have reached Movera (no network, timeout).
  offline,

  /// Movera asked the rider to slow down (HTTP 429).
  rateLimited,

  /// Movera failed on its side (HTTP 5xx).
  serverTrouble,

  /// Movera answered and said no (other HTTP 4xx).
  refused,

  /// Anything else, including errors inside the app.
  unknown,
}

RiderErrorKind riderErrorKind(Object error) {
  if (error is http.ClientException || error is TimeoutException) {
    return RiderErrorKind.offline;
  }
  if (error is ApiError) {
    if (error.code == 'NETWORK' || error.code == 'TIMEOUT') {
      return RiderErrorKind.offline;
    }
    final status = error.statusCode ?? 0;
    // Contract code `rate_limited` (R-O4: lower case).
    if (status == 429 ||
        error.detail == 'rate_limited' ||
        error.detail == 'too_many_requests') {
      return RiderErrorKind.rateLimited;
    }
    if (status >= 500) return RiderErrorKind.serverTrouble;
    if (status >= 400) return RiderErrorKind.refused;
  }
  return RiderErrorKind.unknown;
}

/// R-O2 (owner's wording): what the rider is told when a command was
/// refused because the trip changed just before it (`409 version_mismatch`),
/// or a queued one was dropped because it no longer applies.
const String rideJustChangedMessage = 'Your ride just changed, check it again.';

/// How long Movera asked the rider to wait, as "45 seconds", or null.
String? riderRetryWait(Object error) {
  if (error is! ApiError) return null;
  final wait = error.retryAfter;
  if (wait == null || wait <= Duration.zero) return null;
  final s = wait.inSeconds + (wait.inMilliseconds % 1000 == 0 ? 0 : 1);
  return s == 1 ? '1 second' : '$s seconds';
}
