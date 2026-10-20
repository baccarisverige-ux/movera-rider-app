import 'package:movera_rider/core/api/idempotency.dart';

/// One logical booking operation.
///
/// The idempotency key belongs to the operation, not to an individual HTTP
/// request. Retries of the same intent therefore reuse the same key until the
/// operation succeeds or the rider changes the booking intent.
///
/// RIDE-3: the intent is the rider's trip (route, category, payment), not the
/// quote. A retry within [reuseWindow] of the first try is the same booking
/// and resends the first request unchanged ([replay]); after that a new
/// booking gets a new key.
class BookingAttempt {
  BookingAttempt({required this.intentKey, DateTime? startedAt})
    : idempotencyKey = newIdempotencyKey('booking'),
      startedAt = startedAt ?? DateTime.now();

  /// How long an unfinished booking may be retried under the same key.
  static const reuseWindow = Duration(minutes: 5);

  final String intentKey;
  final String idempotencyKey;
  final DateTime startedAt;

  /// RC-04: the request as first sent under [idempotencyKey]. The contract
  /// server answers a different body under the same key with 409, so a
  /// retry of an unfinished attempt sends exactly this again (same quote,
  /// same pin) instead of a re-quoted body. Null until a request was sent.
  Future<String> Function()? replay;

  bool matches(String otherIntentKey, {DateTime? now}) =>
      intentKey == otherIntentKey &&
      (now ?? DateTime.now()).difference(startedAt) < reuseWindow;
}
