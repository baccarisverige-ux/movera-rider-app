import 'package:movera_rider/core/contracts/money.dart';

/// How a fee is worked out (`FeeRule.type`).
enum FeeType { fixed, percent }

/// One cancel-fee rule as Admin › Dispatch › Rider cancel fees publishes it
/// (CONTRACT.md §6, `RiderAppConfig.cancelFees`).
///
/// live: [freeMin] = minutes after accept; reservation: [freeMin] = minutes
/// before pickup. fixed: [value] is minor units; percent: [value] is 0–100
/// of the fare, rounded half-up to a whole minor unit, then clamped to
/// [min] / [max].
class FeeRule {
  const FeeRule({
    required this.freeMin,
    required this.type,
    required this.value,
    this.min,
    this.max,
  });

  final int freeMin;
  final FeeType type;
  final num value;
  final Money? min;
  final Money? max;

  /// Parses the contract shape; null when a required field is missing or
  /// out of range (the caller keeps its seed rule).
  static FeeRule? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final freeMin = raw['freeMin'];
    final value = raw['value'];
    final type = switch (raw['type']) {
      'fixed' => FeeType.fixed,
      'percent' => FeeType.percent,
      _ => null,
    };
    if (freeMin is! int || freeMin < 0 || type == null || value is! num) {
      return null;
    }
    if (value < 0 || (type == FeeType.percent && value > 100)) return null;
    if (type == FeeType.fixed && value != value.roundToDouble()) return null;
    Money? bound(Object? json) => json == null ? null : Money.fromWire(json);
    final min = bound(raw['min']);
    final max = bound(raw['max']);
    if ((raw['min'] != null && min == null) ||
        (raw['max'] != null && max == null)) {
      return null;
    }
    return FeeRule(
      freeMin: freeMin,
      type: type,
      value: value,
      min: min,
      max: max,
    );
  }

  Map<String, Object?> toJson() => {
    'freeMin': freeMin,
    'type': type.name,
    'value': value,
    'min': min?.toJson(),
    'max': max?.toJson(),
  };
}

/// The rider cancel fee (`riderCancelFee()` in the contract), pure.
/// `fixtures/cancel_fees.json` is replayed through it.
abstract final class CancelFeeCalculator {
  /// A live trip, [minutesSinceAccept] after a driver accepted: free while
  /// `minutesSinceAccept < freeMin`.
  static Money live(FeeRule rule, Money fare, int minutesSinceAccept) =>
      minutesSinceAccept < rule.freeMin
      ? Money(0, fare.currency)
      : _charge(rule, fare);

  /// A reservation, [minutesBeforePickup] before its pickup time: free while
  /// `minutesBeforePickup >= freeMin`.
  static Money reservation(FeeRule rule, Money fare, int minutesBeforePickup) =>
      minutesBeforePickup >= rule.freeMin
      ? Money(0, fare.currency)
      : _charge(rule, fare);

  static Money _charge(FeeRule rule, Money fare) {
    var fee = switch (rule.type) {
      FeeType.fixed => rule.value.toInt(),
      // Half-up to a whole minor unit, in integers: (fare × pct × 2 + 100) ~/ 200.
      FeeType.percent => _percentHalfUp(fare.amountMinor, rule.value),
    };
    final min = rule.min;
    final max = rule.max;
    if (min != null && fee < min.amountMinor) fee = min.amountMinor;
    if (max != null && fee > max.amountMinor) fee = max.amountMinor;
    return Money(fee, fare.currency);
  }

  static int _percentHalfUp(int fareMinor, num percent) {
    if (percent == percent.roundToDouble()) {
      return (fareMinor * percent.toInt() * 2 + 100) ~/ 200;
    }
    return (fareMinor * percent / 100 + 0.5).floor();
  }
}
