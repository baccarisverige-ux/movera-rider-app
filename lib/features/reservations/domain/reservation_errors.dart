/// Book for later is switched off in this build (release until the server
/// reservation resource exists, ARCH-7 / contract C-8).
class ReservationsUnavailableException implements Exception {
  const ReservationsUnavailableException();

  @override
  String toString() =>
      'ReservationsUnavailableException(scheduling is not available)';
}

/// A scheduled ride needs the server's quote for its price (ARCH-16): the
/// rider is never booked at a catalog price the server did not quote.
class ScheduledQuoteRequiredException implements Exception {
  const ScheduledQuoteRequiredException(this.categoryId);

  final String categoryId;

  @override
  String toString() => 'ScheduledQuoteRequiredException($categoryId)';
}

/// Contract v0.18.17 Book later (`contract.json#bookLater.errors`): the
/// server refused a booked ride or a change for a rule of the zone. [limit]
/// is the zone's number in the server's answer (minutes or days).
class BookLaterRefusedException implements Exception {
  const BookLaterRefusedException(this.reason, {this.limit});

  /// `booking_too_soon`, `booking_too_far`, `trip_too_long` or
  /// `change_too_late`.
  final String reason;
  final int? limit;

  static const reasons = {
    'booking_too_soon',
    'booking_too_far',
    'trip_too_long',
    'change_too_late',
  };

  @override
  String toString() => 'BookLaterRefusedException($reason, $limit)';
}
