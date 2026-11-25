import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/contracts/server_clock.dart';

/// Server-owned fare quote. The app displays it; it does not invent prices.
class RideQuote {
  const RideQuote({
    required this.id,
    required this.rideType,
    required this.totalMinor,
    required this.currency,
    required this.expiresAt,
    this.baseMinor = 0,
    this.distanceMinor = 0,
    this.timeMinor = 0,
    this.bookingFeeMinor = 0,
    this.surgeMinor = 0,
    this.discountMinor = 0,
    this.outstandingFeeMinor = 0,
    this.walletDebt,
    this.signedPayload,
    this.serverHeld = false,
    this.pickupAt,
    this.samePointWarning,
    this.tripSeconds,
  });

  final String id;
  final String rideType;
  final int totalMinor;
  final String currency;
  final DateTime expiresAt;
  final int baseMinor;
  final int distanceMinor;
  final int timeMinor;
  final int bookingFeeMinor;
  final int surgeMinor;
  final int discountMinor;

  /// Live sweep 2026-11-02 M-1: an earlier unpaid fee (cancel or no-show)
  /// the server adds to this price (`fareLines.outstanding_fee`), shown as
  /// its own line so it is never hidden in the total.
  final int outstandingFeeMinor;

  /// J10 (contract v0.18.84 `Quote.walletDebt`, `debtModel.quoteInfo`,
  /// owner Q-S5-5): what the rider owes from earlier trips in the quote's
  /// currency, as the server sent it. Information only: it is NOT in
  /// [totalMinor] and not a fare line; it is added once, when the trip is
  /// paid. Null when the server sent none (a balance ≥ 0).
  final Money? walletDebt;
  final String? signedPayload;

  /// A contract `Quote` (openapi v0.5): the server stores it and binds the
  /// trip to it by [id] alone, so it carries no [signedPayload].
  final bool serverHeld;

  /// FIX JOB 7 (contract v0.18.30 `Quote.pickupAt`, owner Q8 "only for
  /// booked rides"): the pickup time of a booked ride; null on a live quote,
  /// which shows no pickup time.
  final DateTime? pickupAt;

  /// FIX JOB 7 (contract v0.18.30 `QuoteList.warnings`, owner Q9 "warn him
  /// but can accept booking"): pickup and drop-off are this close; the
  /// rider is warned and can still book ([bookable] does not change).
  final SamePointWarning? samePointWarning;

  /// v0.18.163 (contract.json#liveTraffic.quote / rider, owner 2026-11-25
  /// "Google trafic réel"): the trip time the server priced with (live
  /// traffic), shown instead of the app's own straight-line minutes. Null
  /// from an older server (then the app's estimate).
  final int? tripSeconds;

  /// [tripSeconds] in whole minutes (at least 1), or null.
  int? get tripMinutes {
    final seconds = tripSeconds;
    if (seconds == null) return null;
    final minutes = (seconds / 60).ceil();
    return minutes < 1 ? 1 : minutes;
  }

  /// Whether booking may send this quote: it has an id and either the
  /// server holds it ([serverHeld]) or it carries the mock's signature.
  bool get bookable =>
      id.trim().isNotEmpty &&
      (serverHeld || (signedPayload?.trim().isNotEmpty ?? false));

  /// rider-r4-32: [expiresAt] is server time, judged on the server clock.
  bool get expired => ServerClock.now().isAfter(expiresAt);
}

/// `QuoteWarning { reason: same_pickup_dropoff, meters, limitMeters }`.
class SamePointWarning {
  const SamePointWarning({required this.meters, required this.limitMeters});

  final int meters;
  final int limitMeters;

  /// The warning in a `QuoteList`, or null when it has none.
  static SamePointWarning? fromQuoteList(Object? warnings) {
    if (warnings is! List) return null;
    for (final item in warnings) {
      if (item is Map &&
          item['reason'] == 'same_pickup_dropoff' &&
          item['meters'] is num &&
          item['limitMeters'] is num) {
        return SamePointWarning(
          meters: (item['meters'] as num).round(),
          limitMeters: (item['limitMeters'] as num).round(),
        );
      }
    }
    return null;
  }
}
