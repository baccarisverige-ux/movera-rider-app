import 'package:movera_rider/core/config/live_data_only.dart';
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

  /// v0.18.49 §71 (owner Q10 update): a booked ride's cancel is always free
  /// for this long after booking (`contract.json#afterTestRules.bookedCancel
  /// .graceAfterBookingMin`, a fixed contract value, not an admin setting).
  static const cancelGraceAfterBooking = Duration(minutes: 5);

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
  /// [categoryRule] is the zone's rule for the ride's category
  /// (`RiderAppConfig.cancelFees.reservation[categoryId]`, X3); without one
  /// the single rule above applies. Free until the rule's window before
  /// pickup; after that its fee, worked out on the ride's fare in the
  /// ride's currency. A ride whose pickup time has passed without a driver
  /// is always free: Movera did not deliver it.
  ReservationCancelTerms cancelTermsFor(
    Reservation ride,
    DateTime now, {
    FeeRule? categoryRule,
  }) {
    final fare = Money.fromLegacyMajor(ride.price, ride.currency);
    // rider-r4-14: the single rule's fee is in its own currency; it never
    // prices a ride in another one (no "50 kr" stamped as 50,00 €). Without
    // a rule of the ride's zone the window stays and the cancel is free.
    final rule =
        categoryRule ??
        (lateCancelFee.currency == fare.currency
            ? feeRule
            : FeeRule(
                freeMin: freeCancelMinutesBeforePickup,
                type: FeeType.fixed,
                value: 0,
              ));
    final window = Duration(minutes: rule.freeMin);
    // v0.18.92 (BQ-M22, contract priceDisplay.cancelPreview): the server's
    // preview of this booked ride wins — its fee now, and from freeUntil on
    // feeAfterFree (a clock compare); the rule below is for demo builds.
    final preview = ride.cancelPreview;
    if (preview != null) {
      final current = preview.at(now);
      final until = preview.freeUntil;
      return ReservationCancelTerms(
        at: now,
        // No step ahead (supervisor S6): the free cancel has ended (or it
        // stays free); no moment is named as its end.
        freeUntil: until ?? now,
        freeEndKnown: until != null,
        // How long before pickup the server's free cancel ends (a time,
        // not money).
        window: until == null
            ? Duration.zero
            : ride.scheduledPickupAt.difference(until),
        lateFee: preview.feeAfterFree ?? preview.feeNow,
        fee: current.fee.isPositive ? current.fee : null,
        timeZone: ride.timeZone,
      );
    }
    // Supervisor MF1 (contract priceDisplay.cancelPreview.apps: "Absent →
    // no amount on the sheet, never a worked-out fee"; owner: the apps never
    // work money out): a real build without the server's preview shows no
    // amount and no free line. The calculator below is for demo builds.
    if (LiveDataOnly.on) {
      return ReservationCancelTerms.unknown(
        at: now,
        currency: fare.currency,
        timeZone: ride.timeZone,
      );
    }
    final freeUntil = ride.scheduledPickupAt.subtract(window);
    final missedByMovera =
        ride.driver == null && !now.isBefore(ride.scheduledPickupAt);
    // Contract v0.3.0: the shared FeeRule calculator decides (reservation:
    // free while minutesBeforePickup >= freeMin), replayed against
    // fixtures/cancel_fees.json.
    final fee = CancelFeeCalculator.reservation(
      rule,
      fare,
      ride.scheduledPickupAt.difference(now).inMinutes,
    );
    // The fee a cancel inside the window costs (a percent rule depends on
    // the fare, so it is worked out for this ride), from the same rule as
    // [fee] so the two lines always agree.
    final lateFee = CancelFeeCalculator.reservation(
      rule,
      fare,
      rule.freeMin - 1,
    );
    final sinceBooking = now.difference(ride.createdAt);
    final inGrace =
        !sinceBooking.isNegative && sinceBooking < cancelGraceAfterBooking;
    final charged = fee.isPositive && !missedByMovera && !inGrace;
    return ReservationCancelTerms(
      at: now,
      freeUntil: freeUntil,
      window: window,
      lateFee: lateFee,
      fee: charged ? fee : null,
      timeZone: ride.timeZone,
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
    this.timeZone,
    this.freeEndKnown = true,
    this.known = true,
  });

  /// BQ-M22 supervisor MF1: a real build without the server's
  /// `cancelPreview`: no amount and no free line (never a phone-worked fee).
  ReservationCancelTerms.unknown({
    required this.at,
    required String currency,
    this.timeZone,
  }) : freeUntil = at,
       window = Duration.zero,
       lateFee = Money(0, currency),
       fee = null,
       freeEndKnown = false,
       known = false;

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

  /// Owner decision 9: the ride's pickup zone, whose clock [freeUntil] is
  /// shown in. Null: the device's.
  final String? timeZone;

  /// Whether [freeUntil] is a real free-cancel end (false: the server sent
  /// no step, supervisor S6; [freeUntil] is then [at] and never shown).
  final bool freeEndKnown;

  /// Whether the cancel cost is known (false: [ReservationCancelTerms.unknown]).
  final bool known;

  bool get isFree => fee == null;

  /// Free now because the free window is still open (and a fee follows it).
  bool get freeForNow =>
      known &&
      freeEndKnown &&
      isFree &&
      lateFee.isPositive &&
      at.isBefore(freeUntil);
}

/// Where the current rules come from. The app reads them over the API;
/// tests pass their own.
abstract class ScheduledRideRulesSource {
  /// The published rules, or null when they cannot be read right now.
  Future<ScheduledRideRules?> fetch();
}
