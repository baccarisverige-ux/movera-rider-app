import 'package:flutter/foundation.dart';
import 'package:movera_rider/core/contracts/money.dart';

/// What the rider owes in unpaid cash fees (contract v0.18.7
/// `pickupWaiting.debtByCurrency`): `Rider.outstanding` is the oldest owed
/// currency, `Rider.outstandingByCurrency` every currency with a debt. An
/// owed fee is charged again only on a trip in the SAME currency, so the
/// app shows each currency on its own and never adds them up.
class RiderOutstanding {
  const RiderOutstanding({this.byCurrency = const []});

  /// One entry per currency, the oldest debt first. Empty = nothing owed.
  final List<Money> byCurrency;

  bool get owesAnything => byCurrency.any((m) => m.isPositive);

  /// What is owed in [currency], or null: the only debt a quote in that
  /// currency ever carries.
  Money? inCurrency(String currency) {
    for (final money in byCurrency) {
      if (money.currency == currency && money.isPositive) return money;
    }
    return null;
  }

  /// Reads the contract `Rider`: `outstandingByCurrency` first, else the
  /// older single `outstanding`.
  static RiderOutstanding fromRider(Map<dynamic, dynamic> rider) {
    final raw = rider['outstandingByCurrency'];
    final list = <Money>[];
    if (raw is List) {
      for (final item in raw) {
        final money = Money.fromWire(item);
        if (money != null &&
            money.isPositive &&
            !list.any((m) => m.currency == money.currency)) {
          list.add(money);
        }
      }
    }
    if (list.isEmpty) {
      final single = Money.fromWire(rider['outstanding']);
      if (single != null && single.isPositive) list.add(single);
    }
    return RiderOutstanding(byCurrency: List.unmodifiable(list));
  }

  /// The signed-in rider's debt as the server last said it; the account
  /// page listens. Reset at sign-out.
  static final ValueNotifier<RiderOutstanding> current = ValueNotifier(
    const RiderOutstanding(),
  );

  static void reset() => current.value = const RiderOutstanding();
}
