import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/features/finding_driver/domain/cancellation_reason.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';
import 'package:movera_rider/features/reservations/domain/scheduled_ride_rules.dart';
import 'package:movera_rider/shared/formatters/money.dart';
import 'package:movera_rider/shared/formatters/place_format.dart';

abstract final class ReservationFormat {
  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// What the rider pays: the server's final amount when known (an
  /// ended-early trip), else the booked price.
  static String price(Reservation ride) {
    final charged = ride.chargedFare;
    return charged != null ? formatMoney(charged) : formatKr(ride.price);
  }

  /// UI-06: the chip on a finished ride in History. Driver-dispatch badges
  /// ("Driver pending" / "Driver assigned") mean nothing once a ride is over.
  static String? historyStatus(Reservation ride) {
    switch (ride.status) {
      case ReservationStatus.completed:
        return 'Completed';
      case ReservationStatus.cancelled:
        if (ride.endedEarly) return 'Ended early';
        final fee = ride.cancellationFee;
        if (fee != null && fee.isPositive) {
          return 'Cancelled · fee ${money(fee)}';
        }
        return 'Cancelled';
      default:
        return null;
    }
  }

  static const _reasonLabels = <String, String>{
    'rider_no_show': 'No-show',
    'system_no_driver': 'No driver found',
    'system_payment_failed': 'Payment problem',
    'system_zone_closed': 'Service area closed',
    'system_error': 'Something went wrong',
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
    if (value.startsWith('admin_')) return 'Cancelled by Movera';
    if (RegExp(r'^[a-z0-9]+(_[a-z0-9]+)+$').hasMatch(value)) {
      final words = value.replaceAll('_', ' ');
      return '${words[0].toUpperCase()}${words.substring(1)}';
    }
    return value;
  }

  static String _weekday(DateTime when) => _weekdays[when.weekday - 1];

  static String _month(DateTime when) => _months[when.month - 1];

  static String time(DateTime when) {
    final hour = when.hour.toString().padLeft(2, '0');
    final minute = when.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  static String weekdayDate(DateTime when) {
    return '${_weekday(when)}, ${when.day} ${_month(when)}';
  }

  static String longDate(DateTime when) {
    return '${_weekday(when)}, ${when.day} ${_month(when)} ${when.year}';
  }

  static String reservedHeadline(DateTime when) {
    return 'Your ride is reserved for ${weekdayDate(when)} at ${time(when)}';
  }

  static String scheduledReady(DateTime when) {
    return "We'll keep your reservation ready for ${weekdayDate(when)} at ${time(when)}.";
  }

  static const String notifyWhenAssigned =
      "We'll notify you as soon as a driver is assigned.";

  static String kr(double amount) => formatKr(amount);

  static String remainingCompact(DateTime when, {DateTime? now}) {
    final left = when.difference(now ?? DateTime.now());
    if (left.inSeconds < 60) return 'Now';
    final days = left.inDays;
    final hours = left.inHours % 24;
    final minutes = left.inMinutes % 60;
    if (days > 0) {
      return hours > 0 ? '${days}d ${hours}h' : '${days}d';
    }
    if (hours > 0) {
      return minutes > 0 ? '${hours}h ${minutes}m' : '${hours}h';
    }
    return '${minutes}m';
  }

  static ({String primary, String? secondary}) remainingParts(
    DateTime when, {
    DateTime? now,
  }) {
    final left = when.difference(now ?? DateTime.now());
    if (left.inSeconds < 60) {
      return (primary: 'Now', secondary: null);
    }
    final days = left.inDays;
    final hours = left.inHours % 24;
    final minutes = left.inMinutes % 60;
    if (days > 0) {
      return (primary: '${days}d', secondary: hours > 0 ? '${hours}h' : null);
    }
    if (hours > 0) {
      return (
        primary: '${hours}h',
        secondary: minutes > 0 ? '${minutes}m' : null,
      );
    }
    return (primary: '${minutes}m', secondary: null);
  }

  static String shortPlace(String raw) => shortenPlace(raw);

  static String cardDate(DateTime when) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(when.year, when.month, when.day);
    if (day == today) return 'Today, ${when.day} ${_month(when)}';
    if (day == today.add(const Duration(days: 1))) {
      return 'Tomorrow, ${when.day} ${_month(when)}';
    }
    return weekdayDate(when);
  }

  static String pickupAt(DateTime when) => 'Pickup at ${time(when)}';

  static String dropoffAt(DateTime when) => 'Dropoff around ${time(when)}';

  static String statusTitle(Reservation ride) {
    switch (ride.status) {
      case ReservationStatus.cancelled:
        return 'Reservation cancelled';
      case ReservationStatus.completed:
        return 'Ride completed';
      case ReservationStatus.driverAssigned:
      case ReservationStatus.driverEnRoute:
        return 'Driver assigned';
      case ReservationStatus.driverArrived:
        return 'Driver has arrived';
      case ReservationStatus.inProgress:
        return 'Ride in progress';
      case ReservationStatus.scheduled:
      case ReservationStatus.driverAssignmentPending:
        return 'Reservation confirmed';
    }
  }

  static String statusBody(
    Reservation ride, {
    required String assignmentDisclaimer,
  }) {
    switch (ride.status) {
      case ReservationStatus.cancelled:
        return ride.cancellationReason == null ||
                ride.cancellationReason!.isEmpty
            ? 'This reservation was cancelled. Details stay in your ride history.'
            : 'Cancelled. ${reasonLabel(ride.cancellationReason!)}';
      case ReservationStatus.completed:
        return 'This scheduled ride is complete.';
      case ReservationStatus.driverAssigned:
      case ReservationStatus.driverEnRoute:
      case ReservationStatus.driverArrived:
      case ReservationStatus.inProgress:
        final driver = ride.driver;
        if (driver == null) {
          return 'A driver has been assigned to this reservation.';
        }
        return '${driver.firstName} is assigned to this reservation.';
      case ReservationStatus.scheduled:
      case ReservationStatus.driverAssignmentPending:
        return assignmentDisclaimer;
    }
  }

  static String driverBadge(Reservation ride) {
    if (ride.driverAssigned) return 'Driver assigned';
    return 'Driver pending';
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
    if (hours == 0) return '$minutes min';
    if (minutes == 0) return '$hours h';
    return '$hours h $minutes min';
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
    if (fee != null) return 'Cancellation fee: ${money(fee)}';
    if (terms.freeForNow) {
      return 'Free to cancel until ${moment(terms.freeUntil, now: terms.at)}';
    }
    return 'Free cancellation';
  }

  /// Cancel sheet detail for [terms].
  static String cancelTermsBody(ReservationCancelTerms terms) {
    final until = moment(terms.freeUntil, now: terms.at);
    final before = window(terms.window);
    final fee = terms.fee;
    if (fee != null) {
      return 'Free cancellation ended at $until, $before before pickup. '
          'You pay ${money(fee)} if you cancel now.';
    }
    if (terms.freeForNow) {
      return 'That is $before before pickup. After that, '
          'cancelling costs ${money(terms.lateFee)}.';
    }
    return 'No fee to cancel this ride.';
  }

  /// "Things to know" cancellation line.
  static String cancellationSummary(ReservationCancelTerms terms) {
    if (!terms.lateFee.isPositive) return 'Free to cancel at any time.';
    final before = window(terms.window);
    final until = moment(terms.freeUntil, now: terms.at);
    if (terms.fee != null) {
      return 'Free cancellation ended at $until, $before before pickup. '
          'Cancelling now costs ${money(terms.fee!)}.';
    }
    if (terms.freeForNow) {
      return 'Free until $until ($before before pickup). '
          'After that, cancelling costs ${money(terms.lateFee)}.';
    }
    return 'No fee to cancel this ride.';
  }

  /// The admin cancel rule in one line, for the terms page.
  static String cancelRule(ScheduledRideRules rules) {
    if (!rules.lateCancelFee.isPositive) {
      return 'Cancelling a scheduled ride is free.';
    }
    return 'Cancelling is free until ${window(rules.freeCancelWindow)} '
        'before pickup. After that, it costs ${money(rules.lateCancelFee)}.';
  }

  static const String driverChangedTitle = 'Your driver changed';

  static String driverChangedBody(
    ReservationDriver previous,
    ReservationDriver current,
  ) {
    return '${previous.displayFirstName} can no longer drive you. '
        '${current.displayFirstName} accepted your ride.';
  }

  static const String driverLeftTitle = 'Finding a new driver';

  static String driverLeftBody(ReservationDriver previous) {
    return "${previous.displayFirstName} can no longer drive you. "
        "We're finding you a new driver.";
  }
}
