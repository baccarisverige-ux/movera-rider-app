import 'money.dart';

/// Contract v0.18.6 `dispatch.raisePrice` (owner G4-E4 "2×, admin can
/// change"): while the search is on, the rider may raise the fare to at most
/// `maxFactor` × the booked fare. The admin sets the factor per zone in
/// Dispatch (`DispatchDocument.raisePrice.maxFactor`, range 1–3, default 2);
/// the rider app reads it as `RiderAppConfig.raisePrice.maxFactor`. The
/// server refuses a raise above it (400 `raise_too_high`). Same in SE and FR.
class RaiseLimit {
  const RaiseLimit._();

  /// `contract.json#dispatch.raisePrice.maxFactor`.
  static const double defaultMaxFactor = 2;

  /// `contract.json#dispatch.raisePrice.range`.
  static const double lowestFactor = 1;
  static const double highestFactor = 3;

  /// The server's reason for a raise above the limit.
  static const String tooHighReason = 'raise_too_high';

  /// [raw] as a factor when it is a number inside the contract's range,
  /// else null (the caller keeps its last good value or the default).
  static double? validFactor(Object? raw) {
    if (raw is! num || !raw.isFinite) return null;
    final value = raw.toDouble();
    return value >= lowestFactor && value <= highestFactor ? value : null;
  }

  /// The highest fare, in minor units, the server accepts for a trip booked
  /// at [bookedMinor]: the fare may not pass `factor × booked`.
  static int ceilingMinor(int bookedMinor, double factor) =>
      (bookedMinor * factor + 1e-9).floor();

  /// The booked fare of a trip projection in [currency], in minor units:
  /// `quote.total` when the server sends it, else `fare` minus every
  /// `rider_raise` fare line. Null when neither can be read.
  static int? bookedFareMinorOf(Map<dynamic, dynamic> ride, String currency) {
    final quote = ride['quote'];
    final total = Money.fromWire(quote is Map ? quote['total'] : null);
    if (total != null && total.isPositive && total.currency == currency) {
      return total.amountMinor;
    }
    final fare = Money.fromWire(ride['fare']);
    final lines = ride['fareLines'];
    if (fare == null || fare.currency != currency || lines is! List) {
      return null;
    }
    var booked = fare.amountMinor;
    for (final line in lines) {
      if (line is! Map || line['code'] != 'rider_raise') continue;
      final amount = Money.fromWire(line['amount']);
      if (amount == null || amount.currency != currency) return null;
      booked -= amount.amountMinor;
    }
    return booked > 0 ? booked : null;
  }
}
