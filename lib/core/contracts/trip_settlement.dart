/// Payment and rating as the shared contract (v0.3.0) carries them: fields
/// on the trip projection, never trip statuses (`contract.json#paymentStatus`,
/// `#ratingStatus`). After `completed` they keep changing through
/// `payment_updated` / `rating_updated` events.
///
/// The Rider UI enums in `features/payments` and `features/ratings` stay
/// presentation types; this file is the wire vocabulary.
library;

enum TripPaymentStatus {
  pending,
  authorized,
  captured,
  failed,
  refunded,
  partiallyRefunded,
}

extension TripPaymentStatusWire on TripPaymentStatus {
  String get wireName => switch (this) {
    TripPaymentStatus.pending => 'pending',
    TripPaymentStatus.authorized => 'authorized',
    TripPaymentStatus.captured => 'captured',
    TripPaymentStatus.failed => 'failed',
    TripPaymentStatus.refunded => 'refunded',
    TripPaymentStatus.partiallyRefunded => 'partially_refunded',
  };

  /// Money has left the rider (or come back): the receipt is final.
  bool get isSettled =>
      this == TripPaymentStatus.captured ||
      this == TripPaymentStatus.refunded ||
      this == TripPaymentStatus.partiallyRefunded;

  static TripPaymentStatus? parse(Object? raw) {
    if (raw is! String) return null;
    final name = raw.trim();
    for (final value in TripPaymentStatus.values) {
      if (value.wireName == name) return value;
    }
    return null;
  }
}

enum TripRatingStatus { notRequested, pending, submitted, skipped }

extension TripRatingStatusWire on TripRatingStatus {
  String get wireName => switch (this) {
    TripRatingStatus.notRequested => 'not_requested',
    TripRatingStatus.pending => 'pending',
    TripRatingStatus.submitted => 'submitted',
    TripRatingStatus.skipped => 'skipped',
  };

  static TripRatingStatus? parse(Object? raw) {
    if (raw is! String) return null;
    final name = raw.trim();
    for (final value in TripRatingStatus.values) {
      if (value.wireName == name) return value;
    }
    return null;
  }
}

/// `contract.json#paymentTransitions`, for the stand-in server.
const Map<TripPaymentStatus, Set<TripPaymentStatus>> tripPaymentTransitions = {
  TripPaymentStatus.pending: {
    TripPaymentStatus.authorized,
    TripPaymentStatus.failed,
  },
  TripPaymentStatus.authorized: {
    TripPaymentStatus.captured,
    TripPaymentStatus.failed,
  },
  TripPaymentStatus.failed: {TripPaymentStatus.authorized},
  TripPaymentStatus.captured: {
    TripPaymentStatus.refunded,
    TripPaymentStatus.partiallyRefunded,
  },
  TripPaymentStatus.partiallyRefunded: {TripPaymentStatus.refunded},
};

/// `contract.json#ratingTransitions`.
const Map<TripRatingStatus, Set<TripRatingStatus>> tripRatingTransitions = {
  TripRatingStatus.notRequested: {TripRatingStatus.pending},
  TripRatingStatus.pending: {
    TripRatingStatus.submitted,
    TripRatingStatus.skipped,
  },
};
