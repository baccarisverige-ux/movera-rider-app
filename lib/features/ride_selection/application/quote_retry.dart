import 'dart:async';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:movera_rider/core/api/api_error.dart';

/// contract.json#fastDispatch.clients: "All three apps treat 503 unavailable
/// (server_busy) like 429: retryable, wait Retry-After (else a short
/// backoff), then try again; nothing is shown as a failure while retries
/// remain."
///
/// Select ride asks for its prices again after a round in which a category
/// got a retryable answer (503 / 429 / 5xx, a timeout, no connection): after
/// [first], doubling up to [cap], never sooner than the server's Retry-After
/// (itself taken as at most [cap], so a bad "Retry-After: 3600" cannot hold
/// the prices for an hour),
/// with a little jitter so riders do not come back all at once. After
/// [maxTries] retries in a row it stops ([gaveUp]) and the screen offers
/// "Try again".
class QuoteRetry {
  QuoteRetry({
    this.first = const Duration(seconds: 2),
    this.cap = const Duration(seconds: 30),
    this.maxTries = 5,
    math.Random? random,
  }) : _random = random ?? math.Random();

  final Duration first;
  final Duration cap;
  final int maxTries;
  final math.Random _random;

  int _failures = 0;
  Duration? _next;

  /// Busy rounds in a row.
  int get failures => _failures;

  /// When to ask again; null when no retry is due.
  Duration? get nextWait => _next;

  /// The automatic retries ran out: the rider decides ("Try again").
  bool get gaveUp => _failures > maxTries;

  /// One finished round of quotes. [busy]: some category got a retryable
  /// answer; [retryAfter]: the longest Retry-After among them.
  void record({required bool busy, Duration? retryAfter}) {
    if (!busy) {
      reset();
      return;
    }
    _failures += 1;
    if (gaveUp) {
      _next = null;
      return;
    }
    var step = first * (1 << (_failures - 1));
    if (step > cap) step = cap;
    // ±20 % so a crowd of riders spreads out.
    final jittered = step * (0.8 + 0.4 * _random.nextDouble());
    // Owner: "doubling up to 30 s". A Retry-After longer than [cap] (a
    // proxy's or a wrong value) waits [cap].
    var floor = retryAfter ?? Duration.zero;
    if (floor > cap) floor = cap;
    _next = jittered < floor ? floor : jittered;
  }

  void reset() {
    _failures = 0;
    _next = null;
  }
}

/// A quote failure the server or the network may get over by itself.
bool isRetryableQuoteFailure(Object error) =>
    error is TimeoutException ||
    error is http.ClientException ||
    (error is ApiError && error.isRetryable);
