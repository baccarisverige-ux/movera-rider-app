import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/features/finding_driver/domain/cancellation_reason.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';
import 'package:movera_rider/features/reservations/domain/scheduled_ride_rules.dart';
import 'package:movera_rider/shared/formatters/money.dart';
import 'package:movera_rider/shared/formatters/place_format.dart';
import 'package:movera_rider/l10n/l10n.dart';

abstract final class ReservationFormat {

  /// What the rider pays: the server's final amount when known (an
  /// ended-early trip), else the booked price.
  static String price(Reservation ride) {
    final charged = ride.chargedFare;
    return charged != null
        ? formatMoney(charged)
        : formatMajor(ride.price, ride.currency);
  }

  /// UI-06: the chip on a finished ride in History. Driver-dispatch badges
  /// ("Driver pending" / "Driver assigned") mean nothing once a ride is over.
  static String? historyStatus(Reservation ride) {
    switch (ride.status) {
      case ReservationStatus.completed:
        if (ride.paymentFailed) return L10n.current.resPaymentFailed;
        return L10n.current.resCompleted;
      case ReservationStatus.cancelled:
        if (ride.endedEarly) return L10n.current.endedEarly;
        final fee = ride.cancellationFee;
        if (fee != null && fee.isPositive) {
          return L10n.current.resCancelledFee(money(fee));
        }
        return L10n.current.resCancelled;
      default:
        return null;
    }
  }

  static Map<String, String> get _reasonLabels => <String, String>{
    'rider_no_show': L10n.current.reasonNoShow,
    'system_no_driver': L10n.current.termNoDriverFound,
    'system_payment_failed': L10n.current.reasonPayment,
    'system_zone_closed': L10n.current.reasonZoneClosed,
    'system_error': L10n.current.reasonError,
  };

  /// UI-07: a cancel reason as riders read it. Reason codes
  /// (`plans_changed`) map to their labels; older records already hold a
  /// label ("No driver found") and are shown as they are.
  static String reasonLabel(String raw) {
    final value = raw.trim();
    for (final phase in CancelPhase.values) {
      for (final reason in CancellationReason.forPhase(phase)) {
        if (reason.id == value) return reason.label;
      }
    }
    final known = _reasonLabels[value];
    if (known != null) return known;
    if (value.startsWith('admin_')) return L10n.current.cancelledByMovera;
    if (RegExp(r'^[a-z0-9]+(_[a-z0-9]+)+$').hasMatch(value)) {
      final words = value.replaceAll('_', ' ');
      return '${words[0].toUpperCase()}${words.substring(1)}';
    }
    return value;
  }

  /// "5 Jan", "5 janv.", "5 jan.": intl's month names in the app language.
  static String _dayMonth(DateTime when) => L10n.formatDate(when, 'd MMM');

  static String time(DateTime when) {
    final hour = when.hour.toString().padLeft(2, '0');
    final minute = when.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  static String weekdayDate(DateTime when) {
    return L10n.formatDate(when, 'EEE, d MMM');
  }

  static String longDate(DateTime when) {
    return L10n.formatDate(when, 'EEE, d MMM y');
  }

  static String reservedHeadline(DateTime when) {
    return L10n.current.resReservedFor(weekdayDate(when), time(when));
  }

  static String scheduledReady(DateTime when) {
    return L10n.current.resKeepReady(weekdayDate(when), time(when));
  }

  static String get notifyWhenAssigned => L10n.current.resNotifyAssigned;

  /// [amount] whole units of [currency] (kronor unless the ride says).
  static String kr(double amount, [String currency = 'SEK']) =>
      formatMajor(amount, currency);

  static String remainingCompact(DateTime when, {DateTime? now}) {
    final left = when.difference(now ?? DateTime.now());
    if (left.inSeconds < 60) return L10n.current.now;
    final days = left.inDays;
    final hours = left.inHours % 24;
    final minutes = left.inMinutes % 60;
    if (days > 0) {
      return hours > 0 ? L10n.current.durDaysHours('$days', '$hours') : L10n.current.durDays('$days');
    }
    if (hours > 0) {
      return minutes > 0 ? L10n.current.durHoursMinutes('$hours', '$minutes') : L10n.current.durHours('$hours');
    }
    return L10n.current.durMinutes('$minutes');
  }

  static ({String primary, String? secondary}) remainingParts(
    DateTime when, {
    DateTime? now,
  }) {
    final left = when.difference(now ?? DateTime.now());
    if (left.inSeconds < 60) {
      return (primary: L10n.current.now, secondary: null);
    }
    final days = left.inDays;
    final hours = left.inHours % 24;
    final minutes = left.inMinutes % 60;
    if (days > 0) {
      return (primary: L10n.current.durDays('$days'), secondary: hours > 0 ? L10n.current.durHours('$hours') : null);
    }
    if (hours > 0) {
      return (
        primary: L10n.current.durHours('$hours'),
        secondary: minutes > 0 ? L10n.current.durMinutes('$minutes') : null,
      );
    }
    return (primary: L10n.current.durMinutes('$minutes'), secondary: null);
  }

  static String shortPlace(String raw) => shortenPlace(raw);

  static String cardDate(DateTime when) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(when.year, when.month, when.day);
    if (day == today) return L10n.current.todayDate(_dayMonth(when));
    if (day == today.add(const Duration(days: 1))) {
      return L10n.current.tomorrowDate(_dayMonth(when));
    }
    return weekdayDate(when);
  }

  static String pickupAt(DateTime when) => L10n.current.pickupAtTime(time(when));

  static String dropoffAt(DateTime when) => L10n.current.dropoffAround(time(when));

  static String statusTitle(Reservation ride) {
    switch (ride.status) {
      case ReservationStatus.cancelled:
        return L10n.current.resStatusCancelled;
      case ReservationStatus.completed:
        return L10n.current.resStatusCompleted;
      case ReservationStatus.driverAssigned:
      case ReservationStatus.driverEnRoute:
        return L10n.current.driverAssigned;
      case ReservationStatus.driverArrived:
        return L10n.current.etaDriverArrived;
      case ReservationStatus.inProgress:
        return L10n.current.etaRideInProgress;
      case ReservationStatus.scheduled:
      case ReservationStatus.driverAssignmentPending:
        return L10n.current.resStatusConfirmed;
    }
  }

  /// [showDriver] false (admin's showDriverOnAccept off, driver not yet on
  /// the way) keeps the driver's name out of the body (rider-u163).
  static String statusBody(
    Reservation ride, {
    required String assignmentDisclaimer,
    bool showDriver = true,
  }) {
    switch (ride.status) {
      case ReservationStatus.cancelled:
        return ride.cancellationReason == null ||
                ride.cancellationReason!.isEmpty
            ? L10n.current.resBodyCancelled
            : L10n.current.resBodyCancelledReason(reasonLabel(ride.cancellationReason!));
      case ReservationStatus.completed:
        return L10n.current.resBodyCompleted;
      case ReservationStatus.driverAssigned:
      case ReservationStatus.driverEnRoute:
      case ReservationStatus.driverArrived:
      case ReservationStatus.inProgress:
        final driver = ride.driver;
        if (driver == null || !showDriver) {
          return L10n.current.resBodyDriverAssigned;
        }
        return L10n.current.resBodyNameAssigned(driver.firstName);
      case ReservationStatus.scheduled:
      case ReservationStatus.driverAssignmentPending:
        return assignmentDisclaimer;
    }
  }

  static String driverBadge(Reservation ride) {
    if (ride.driverAssigned) return L10n.current.driverAssigned;
    return L10n.current.driverPending;
  }

  static String historyWhen(Reservation ride) {
    return '${cardDate(ride.scheduledPickupAt)} · ${time(ride.scheduledPickupAt)}';
  }

  /// "50 kr", "5 €": the app's one money format (UI-10).
  static String money(Money amount) => formatMoney(amount);

  /// "1 h", "1 h 30 min", "45 min".
  static String window(Duration window) {
    final hours = window.inHours;
    final minutes = window.inMinutes % 60;
    if (hours == 0) return L10n.current.durMin('$minutes');
    if (minutes == 0) return L10n.current.durH('$hours');
    return L10n.current.durHMin('$hours', '$minutes');
  }

  /// "06:55" today, else "Mon, 23 Sep, 06:55".
  static String moment(DateTime when, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final sameDay =
        when.year == today.year &&
        when.month == today.month &&
        when.day == today.day;
    return sameDay ? time(when) : '${weekdayDate(when)}, ${time(when)}';
  }

  /// Cancel sheet headline for [terms].
  static String cancelTermsTitle(ReservationCancelTerms terms) {
    final fee = terms.fee;
    if (fee != null) return L10n.current.cancelFee(money(fee));
    if (terms.freeForNow) {
      return L10n.current.freeToCancelUntil(moment(terms.freeUntil, now: terms.at));
    }
    return L10n.current.freeCancellation;
  }

  /// Cancel sheet detail for [terms].
  static String cancelTermsBody(ReservationCancelTerms terms) {
    final until = moment(terms.freeUntil, now: terms.at);
    final before = window(terms.window);
    final fee = terms.fee;
    if (fee != null) {
      return L10n.current.freeEndedPayNow(until, before, money(fee));
    }
    if (terms.freeForNow) {
      return L10n.current.freeThatIsBefore(before, money(terms.lateFee));
    }
    return L10n.current.noFeeToCancel;
  }

  /// "Things to know" cancellation line.
  static String cancellationSummary(ReservationCancelTerms terms) {
    if (!terms.lateFee.isPositive) return L10n.current.freeAnyTime;
    final before = window(terms.window);
    final until = moment(terms.freeUntil, now: terms.at);
    if (terms.fee != null) {
      return L10n.current.freeEndedCostsNow(until, before, money(terms.fee!));
    }
    if (terms.freeForNow) {
      return L10n.current.freeUntilThen(until, before, money(terms.lateFee));
    }
    return L10n.current.noFeeToCancel;
  }

  /// The admin cancel rule in one line, for the terms page.
  static String cancelRule(ScheduledRideRules rules) {
    if (!rules.lateCancelFee.isPositive) {
      return L10n.current.scheduledCancelFree;
    }
    return L10n.current.cancelRuleText(window(rules.freeCancelWindow), money(rules.lateCancelFee));
  }

  /// The cancel rule [terms] apply (rider-u169): the ride's own window
  /// and late fee, which may be its ride type's rule.
  static String cancelRuleOf(ReservationCancelTerms terms) {
    if (!terms.lateFee.isPositive) {
      return L10n.current.scheduledCancelFree;
    }
    return L10n.current.cancelRuleText(window(terms.window), money(terms.lateFee));
  }

  static String get driverChangedTitle => L10n.current.driverChangedTitle;

  static String driverChangedBody(
    ReservationDriver previous,
    ReservationDriver current,
  ) {
    return L10n.current.driverChangedBody(previous.displayFirstName, current.displayFirstName);
  }

  static String get driverLeftTitle => L10n.current.driverLeftTitle;

  /// [showName] false: the leaving driver was never shown (rider-u163).
  static String driverLeftBody(
    ReservationDriver previous, {
    bool showName = true,
  }) {
    if (!showName) return L10n.current.driverLeftBodyUnnamed;
    return L10n.current.driverLeftBody(previous.displayFirstName);
  }
}
