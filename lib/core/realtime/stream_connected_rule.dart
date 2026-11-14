import 'package:movera_rider/core/api/api_error.dart';

/// R3 (owner 2026-11-13 12:23 UTC "Yes, update rule (Rec.)"; contract
/// v0.18.83 `realtime.connectedRule`, one rule for the driver and rider
/// apps): a stream counts as connected only after it delivered an event or
/// stayed up this long; a 200 alone is not connected. Only a connected
/// stream resets the reconnect backoff, so a stream the busy server opens
/// and ends at once is one more failed try and quick repeated closes back
/// off. A `: heartbeat` comment is not an event.
const streamConnectedAfter = Duration(seconds: 30);

/// The longest Retry-After a stream honours (`realtime.connectedRule`).
const streamMaxRetryAfter = Duration(seconds: 60);

/// The wait a refused stream (429 / 503) asks for in its Retry-After, at
/// most [streamMaxRetryAfter]; null for any other error or no header.
Duration? streamRetryAfter(Object? error) {
  if (error is! ApiError) return null;
  final status = error.statusCode;
  if (status != 429 && status != 503) return null;
  final wait = error.retryAfter;
  if (wait == null || wait <= Duration.zero) return null;
  return wait > streamMaxRetryAfter ? streamMaxRetryAfter : wait;
}
