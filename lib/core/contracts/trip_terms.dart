import 'package:movera_rider/core/contracts/cancel_fee.dart';
import 'package:movera_rider/core/contracts/money.dart';

/// `TripProjection.terms` (contract v0.18.7 `pickupWaiting.terms`): the
/// rules this trip is charged by, from booking to the end, in the trip's
/// currency. The rider app shows these and never its own numbers.
class TripTerms {
  const TripTerms({
    required this.currency,
    required this.freeWaitMin,
    required this.waitPerMin,
    required this.noShowAfterMin,
    required this.noShowFee,
    this.noShowDriverSharePct = 0,
    this.cancelRule,
    this.cancelDriverSharePct = 0,
    this.cancelAfterArrivedIsNoShow = true,
    this.maxPickupMoveMeters = defaultMaxPickupMoveMeters,
    this.stopFreeWaitMin = 0,
    this.stopWaitPerMin,
  });

  /// `pickupWaiting.pickupMove.default`.
  static const defaultMaxPickupMoveMeters = 200;

  final String currency;
  final num freeWaitMin;
  final Money waitPerMin;
  final num noShowAfterMin;
  final Money noShowFee;
  final num noShowDriverSharePct;
  final FeeRule? cancelRule;
  final num cancelDriverSharePct;
  final bool cancelAfterArrivedIsNoShow;
  final int maxPickupMoveMeters;

  /// v0.18.8/v0.18.9 (G7 decision 4): free minutes at each middle stop
  /// (default 0 = paid from the first minute) and the price per minute.
  final int stopFreeWaitMin;
  final Money? stopWaitPerMin;

  /// Parses the wire shape; null when a required field is missing or the
  /// amounts are not all in the trip's currency.
  static TripTerms? fromWire(Object? raw) {
    if (raw is! Map) return null;
    final currency = Money.normalizeCurrency(raw['currency']);
    final freeWaitMin = raw['freeWaitMin'];
    final noShowAfterMin = raw['noShowAfterMin'];
    final waitPerMin = Money.fromWire(raw['waitPerMin']);
    final noShowFee = Money.fromWire(raw['noShowFee']);
    if (currency == null ||
        freeWaitMin is! num ||
        noShowAfterMin is! num ||
        waitPerMin == null ||
        noShowFee == null ||
        waitPerMin.currency != currency ||
        noShowFee.currency != currency) {
      return null;
    }
    final share = raw['noShowDriverSharePct'];
    final cancelShare = raw['cancelDriverSharePct'];
    final maxMove = raw['maxPickupMoveMeters'];
    final stopFree = raw['stopFreeWaitMin'];
    final stopPerMin = Money.fromWire(raw['stopWaitPerMin']);
    return TripTerms(
      stopFreeWaitMin: stopFree is num && stopFree >= 0 ? stopFree.round() : 0,
      stopWaitPerMin: stopPerMin != null && stopPerMin.currency == currency
          ? stopPerMin
          : null,
      currency: currency,
      freeWaitMin: freeWaitMin,
      waitPerMin: waitPerMin,
      noShowAfterMin: noShowAfterMin,
      noShowFee: noShowFee,
      noShowDriverSharePct: share is num ? share : 0,
      cancelRule: FeeRule.fromJson(raw['cancelRule']),
      cancelDriverSharePct: cancelShare is num ? cancelShare : 0,
      cancelAfterArrivedIsNoShow: raw['cancelAfterArrivedIsNoShow'] != false,
      maxPickupMoveMeters: maxMove is num && maxMove >= 0
          ? maxMove.round()
          : defaultMaxPickupMoveMeters,
    );
  }

  Map<String, Object?> toWire() => {
    'currency': currency,
    'freeWaitMin': freeWaitMin,
    'waitPerMin': waitPerMin.toJson(),
    'noShowAfterMin': noShowAfterMin,
    'noShowFee': noShowFee.toJson(),
    'noShowDriverSharePct': noShowDriverSharePct,
    'cancelRule': cancelRule?.toJson(),
    'cancelDriverSharePct': cancelDriverSharePct,
    'cancelAfterArrivedIsNoShow': cancelAfterArrivedIsNoShow,
    'maxPickupMoveMeters': maxPickupMoveMeters,
    'stopFreeWaitMin': stopFreeWaitMin,
    'stopWaitPerMin': ?stopWaitPerMin?.toJson(),
  };
}

/// `cancellation.feeKind` (contract v0.18.7 `pickupWaiting.cancelAfterArrived`).
enum CancelFeeKind { cancel, noShow }

/// What the rider is told after a cancel: the fee and which rule set it.
class RiderCancelOutcomeFee {
  const RiderCancelOutcomeFee({required this.fee, required this.kind});

  /// Null = no fee (also while the server has not decided yet).
  final Money? fee;
  final CancelFeeKind? kind;

  bool get charged => fee != null && fee!.isPositive;

  /// Reads `cancellation` of a projection; null when the trip carries none.
  static RiderCancelOutcomeFee? fromProjection(Object? projection) {
    if (projection is! Map) return null;
    final cancellation = projection['cancellation'];
    if (cancellation is! Map) return null;
    final fee = Money.fromWire(cancellation['fee']);
    final kind = switch (cancellation['feeKind']) {
      'no_show' => CancelFeeKind.noShow,
      'cancel' => CancelFeeKind.cancel,
      _ => null,
    };
    return RiderCancelOutcomeFee(
      fee: fee != null && fee.isPositive ? fee : null,
      kind: fee != null && fee.isPositive ? kind : null,
    );
  }
}
