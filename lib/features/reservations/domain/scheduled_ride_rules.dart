import 'package:movera_rider/core/contracts/cancel_fee.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';

/// Rider-side rules for scheduled rides, as Movera admin sets them
/// (Admin › Dispatch › Reservations). The defaults mirror the admin
/// defaults. `GET /api/v1/rider/scheduled-rides/rules` (PROPOSED) feeds the
/// same names, so a backend can take over without a screen change.
class ScheduledRideRules {
  const ScheduledRideRules({
    this.freeCancelMinutesBeforePickup = 60,
    this.lateCancelFee = const Money(5000),
    this.showDriverOnAccept = true,
  });

  /// Used until the server answers, and whenever it cannot.
  static const defaults = ScheduledRideRules();

  /// Longest free-cancel window the rider app accepts (one week).
  static const maxFreeCancelMinutes = 7 * 24 * 60;

  /// The rider cancels for free until this many minutes before pickup.
  final int freeCancelMinutesBeforePickup;

  /// What the rider pays to cancel inside that window. Zero means free.
  final Money lateCancelFee;

  /// The rider sees the driver's name, photo and car as soon as a driver
  /// accepts. Off: only once the driver is on the way.
  final bool showDriverOnAccept;

  /// These rules as a contract FeeRule (fixed late fee).
  FeeRule get feeRule => FeeRule(
    freeMin: freeCancelMinutesBeforePickup,
    type: FeeType.fixed,
    value: lateCancelFee.amountMinor,
  );

  Duration get freeCancelWindow =>
      Duration(minutes: freeCancelMinutesBeforePickup);

  /// Reads the wire shape. A missing or invalid field keeps its value from
  /// [fallback], so a partial answer never invents a rule.
  static ScheduledRideRules fromJson(
    Object? raw, {
    ScheduledRideRules fallback = defaults,
  }) {
    if (raw is! Map) return fallback;
    final minutes = raw['freeCancelMinutesBeforePickup'];
    final validMinutes =
        minutes is num &&
        minutes == minutes.roundToDouble() &&
        minutes >= 0 &&
        minutes <= maxFreeCancelMinutes;
    final feeMinor = raw['lateCancelFeeMinor'];
    final fee = feeMinor is num && feeMinor >= 0
        ? Money.tryMinor(feeMinor, raw['currency'] ?? Money.defaultCurrency)
        : null;
    final showDriver = raw['showDriverOnAccept'];
    return ScheduledRideRules(
      freeCancelMinutesBeforePickup: validMinutes
          ? minutes.toInt()
          : fallback.freeCancelMinutesBeforePickup,
      lateCancelFee: fee ?? fallback.lateCancelFee,
      showDriverOnAccept: showDriver is bool
          ? showDriver
          : fallback.showDriverOnAccept,
    );
  }

  Map<String, Object> toJson() => {
    'freeCancelMinutesBeforePickup': freeCancelMinutesBeforePickup,
    'lateCancelFeeMinor': lateCancelFee.amountMinor,
    'currency': lateCancelFee.currency,
    'showDriverOnAccept': showDriverOnAccept,
  };

  /// What cancelling [ride] at [now] costs the rider.
  ///
  /// Free until [freeCancelWindow] before pickup; after that the admin fee.
  /// A ride whose pickup time has passed without a driver is always free:
  /// Movera did not deliver it.
  ReservationCancelTerms cancelTermsFor(Reservation ride, DateTime now) {
    final freeUntil = ride.scheduledPickupAt.subtract(freeCancelWindow);
    final missedByMovera =
        ride.driver == null && !now.isBefore(ride.scheduledPickupAt);
    // Contract v0.3.0: the shared FeeRule calculator decides (reservation:
    // free while minutesBeforePickup >= freeMin), the same one Driver and
    // Admin replay against fixtures/cancel_fees.json.
    final fee = CancelFeeCalculator.reservation(
      feeRule,
      Money.fromLegacyMajor(ride.price, lateCancelFee.currency),
      ride.scheduledPickupAt.difference(now).inMinutes,
    );
    final charged = fee.isPositive && !missedByMovera;
    return ReservationCancelTerms(
      at: now,
      freeUntil: freeUntil,
      window: freeCancelWindow,
      lateFee: lateCancelFee,
      fee: charged ? fee : null,
    );
  }

  /// Whether the rider sees [ride]'s driver details now.
  bool showsDriverOf(Reservation ride) {
    if (ride.driver == null) return false;
    if (ride.revealsDriver) return true;
    return showDriverOnAccept && ride.driverAssigned;
  }

  @override
  bool operator ==(Object other) =>
      other is ScheduledRideRules &&
      other.freeCancelMinutesBeforePickup == freeCancelMinutesBeforePickup &&
      other.lateCancelFee == lateCancelFee &&
      other.showDriverOnAccept == showDriverOnAccept;

  @override
  int get hashCode => Object.hash(
    freeCancelMinutesBeforePickup,
    lateCancelFee,
    showDriverOnAccept,
  );
}

/// The cost of cancelling one scheduled ride at one moment.
class ReservationCancelTerms {
  const ReservationCancelTerms({
    required this.at,
    required this.freeUntil,
    required this.window,
    required this.lateFee,
    this.fee,
  });

  /// When these terms were worked out.
  final DateTime at;

  /// Last moment the rider can cancel for free.
  final DateTime freeUntil;

  /// How long before pickup free cancellation ends.
  final Duration window;

  /// The admin fee for a cancel after [freeUntil].
  final Money lateFee;

  /// The fee for cancelling at [at], or null when it is free.
  final Money? fee;

  bool get isFree => fee == null;

  /// Free now because the free window is still open (and a fee follows it).
  bool get freeForNow => isFree && lateFee.isPositive && at.isBefore(freeUntil);
}

/// Where the current rules come from. The app reads them over the API;
/// tests pass their own.
abstract class ScheduledRideRulesSource {
  /// The published rules, or null when they cannot be read right now.
  Future<ScheduledRideRules?> fetch();
}
