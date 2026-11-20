import 'package:flutter/foundation.dart';
import 'package:movera_rider/core/contracts/money.dart';

/// Contract v0.18.136 `stripeFees.profile` (DRAFT, Stripe TEST mode; owner
/// 2026-11-20 "So we use stripe"): `Rider.feesPayableByCard`, the owed fees
/// the rider can pay by card or Apple Pay in the app now. Every amount is the
/// server's (min of what is left of the fee and her debt); the app never
/// works one out. Missing or empty = nothing to pay here (switch off, other
/// currency, nothing owed).
class FeePayable {
  const FeePayable({required this.tripId, required this.amount});
  final String tripId;
  final Money amount;
}

class FeesPayableByCard {
  const FeesPayableByCard([this.items = const []]);
  final List<FeePayable> items;

  FeePayable? forTrip(String tripId) {
    for (final item in items) {
      if (item.tripId == tripId) return item;
    }
    return null;
  }

  static FeesPayableByCard fromRider(Map<dynamic, dynamic> rider) {
    final raw = rider['feesPayableByCard'];
    if (raw is! List) return const FeesPayableByCard();
    final out = <FeePayable>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final tripId = item['tripId'];
      final amount = Money.fromWire(item['amount']);
      if (tripId is String &&
          tripId.isNotEmpty &&
          amount != null &&
          amount.isPositive) {
        out.add(FeePayable(tripId: tripId, amount: amount));
      }
    }
    return FeesPayableByCard(List.unmodifiable(out));
  }

  /// What the server last said; the account page and the cancel notice listen.
  static final ValueNotifier<FeesPayableByCard> current = ValueNotifier(
    const FeesPayableByCard(),
  );

  static void reset() => current.value = const FeesPayableByCard();
}
