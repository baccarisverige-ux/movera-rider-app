import 'package:movera_rider/core/contracts/ride_status.dart';
import 'package:movera_rider/core/contracts/trip_settlement.dart';

/// Canonical trip lifecycle, `contract.json#tripStatus` (v0.3.0, 19 values).
/// Payment and rating are separate fields, never statuses.
///
/// [RideStatus] stays the Rider UI/session enum. Map through [tripStatus]
/// and [RideStatusWire.fromProjection].
enum TripStatus {
  draft,
  quoted,
  requested,
  searching,
  offered,
  accepted,
  driverToPickup,
  arrived,
  riderOnboard,
  inTrip,
  approachingDropoff,
  completed,
  cancelledByRider,
  cancelledByDriver,
  cancelledByAdmin,
  cancelledBySystem,
  noShow,
  expired,
  failed,
}

/// `contract.json#tripStatus.terminal`.
const Set<TripStatus> tripTerminalStatuses = {
  TripStatus.completed,
  TripStatus.cancelledByRider,
  TripStatus.cancelledByDriver,
  TripStatus.cancelledByAdmin,
  TripStatus.cancelledBySystem,
  TripStatus.noShow,
  TripStatus.expired,
  TripStatus.failed,
};

/// `contract.json#tripStatus.driverAssigned`.
const Set<TripStatus> tripDriverAssignedStatuses = {
  TripStatus.accepted,
  TripStatus.driverToPickup,
  TripStatus.arrived,
  TripStatus.riderOnboard,
  TripStatus.inTrip,
  TripStatus.approachingDropoff,
};

/// `contract.json#tripStatus.riderOnboard`.
const Set<TripStatus> tripRiderOnboardStatuses = {
  TripStatus.riderOnboard,
  TripStatus.inTrip,
  TripStatus.approachingDropoff,
};

extension TripStatusWire on TripStatus {
  String get wireName => switch (this) {
        TripStatus.draft => 'draft',
        TripStatus.quoted => 'quoted',
        TripStatus.requested => 'requested',
        TripStatus.searching => 'searching',
        TripStatus.offered => 'offered',
        TripStatus.accepted => 'accepted',
        TripStatus.driverToPickup => 'driver_to_pickup',
        TripStatus.arrived => 'arrived',
        TripStatus.riderOnboard => 'rider_onboard',
        TripStatus.inTrip => 'in_trip',
        TripStatus.approachingDropoff => 'approaching_dropoff',
        TripStatus.completed => 'completed',
        TripStatus.cancelledByRider => 'cancelled_by_rider',
        TripStatus.cancelledByDriver => 'cancelled_by_driver',
        TripStatus.cancelledByAdmin => 'cancelled_by_admin',
        TripStatus.cancelledBySystem => 'cancelled_by_system',
        TripStatus.noShow => 'no_show',
        TripStatus.expired => 'expired',
        TripStatus.failed => 'failed',
      };

  bool get isTerminal => tripTerminalStatuses.contains(this);

  bool get hasDriver => tripDriverAssignedStatuses.contains(this);

  /// Parses a contract snake_case wire name. Unknown values return null so
  /// the caller decides how to surface a contract mismatch.
  static TripStatus? parse(Object? raw) {
    if (raw is! String) return null;
    final name = raw.trim();
    for (final status in TripStatus.values) {
      if (status.wireName == name) return status;
    }
    return null;
  }
}

extension RideStatusAsTripStatus on RideStatus {
  /// The trip status this UI state stands for. Several UI states share one
  /// trip status (every post-trip state is `completed`; `noDriverFound` and
  /// `bookingExpired` are both `expired`); the reverse direction needs the
  /// projection's payment and rating fields, see
  /// [RideStatusWire.fromProjection].
  TripStatus get tripStatus => switch (this) {
        RideStatus.idle ||
        RideStatus.pickupSelected ||
        RideStatus.destinationSelected =>
          TripStatus.draft,
        RideStatus.quoteLoading ||
        RideStatus.rideOptionsReady ||
        RideStatus.rideSelected ||
        RideStatus.paymentSelected =>
          TripStatus.quoted,
        RideStatus.bookingRequested => TripStatus.requested,
        RideStatus.findingDriver ||
        RideStatus.searchDelayed =>
          TripStatus.searching,
        RideStatus.driverAssigned => TripStatus.accepted,
        RideStatus.driverArriving => TripStatus.driverToPickup,
        RideStatus.driverWaiting => TripStatus.arrived,
        RideStatus.tripStarted => TripStatus.riderOnboard,
        RideStatus.tripInProgress => TripStatus.inTrip,
        RideStatus.approachingDropoff => TripStatus.approachingDropoff,
        RideStatus.tripCompleted ||
        RideStatus.paymentProcessing ||
        RideStatus.paymentFinalized ||
        RideStatus.ratingPending ||
        RideStatus.paymentFailed ||
        RideStatus.closed =>
          TripStatus.completed,
        RideStatus.cancelledByRider => TripStatus.cancelledByRider,
        // The reassignment notice: the trip itself is back in dispatch.
        RideStatus.cancelledByDriver => TripStatus.searching,
        RideStatus.endedByDriver => TripStatus.cancelledByDriver,
        RideStatus.cancelledByAdmin => TripStatus.cancelledByAdmin,
        RideStatus.cancelledBySystem => TripStatus.cancelledBySystem,
        RideStatus.noShow => TripStatus.noShow,
        RideStatus.tripFailed => TripStatus.failed,
        RideStatus.noDriverFound || RideStatus.bookingExpired =>
          TripStatus.expired,
      };
}

/// The one inbound adapter from the wire to the Rider UI enum (ARCH-10).
///
/// Every status read in the app goes through [parse] or [fromProjection]:
/// no other `RideStatus.values` lookup may parse server data.
extension RideStatusWire on RideStatus {
  /// The UI state for [trip], with payment and rating deciding the
  /// post-trip state of a `completed` trip (contract §2: they are fields,
  /// not statuses).
  static RideStatus fromTrip(
    TripStatus trip, {
    TripPaymentStatus? paymentStatus,
    TripRatingStatus? ratingStatus,
  }) => switch (trip) {
        TripStatus.draft => RideStatus.idle,
        TripStatus.quoted => RideStatus.rideOptionsReady,
        TripStatus.requested => RideStatus.bookingRequested,
        // An offer sent to one driver is still a search for the rider.
        TripStatus.searching || TripStatus.offered => RideStatus.findingDriver,
        TripStatus.accepted => RideStatus.driverAssigned,
        TripStatus.driverToPickup => RideStatus.driverArriving,
        TripStatus.arrived => RideStatus.driverWaiting,
        TripStatus.riderOnboard => RideStatus.tripStarted,
        TripStatus.inTrip => RideStatus.tripInProgress,
        TripStatus.approachingDropoff => RideStatus.approachingDropoff,
        TripStatus.completed => _afterCompletion(paymentStatus, ratingStatus),
        TripStatus.cancelledByRider => RideStatus.cancelledByRider,
        TripStatus.cancelledByDriver => RideStatus.endedByDriver,
        TripStatus.cancelledByAdmin => RideStatus.cancelledByAdmin,
        TripStatus.cancelledBySystem => RideStatus.cancelledBySystem,
        TripStatus.noShow => RideStatus.noShow,
        TripStatus.failed => RideStatus.tripFailed,
        TripStatus.expired => RideStatus.noDriverFound,
      };

  static RideStatus _afterCompletion(
    TripPaymentStatus? payment,
    TripRatingStatus? rating,
  ) {
    if (payment == TripPaymentStatus.failed) return RideStatus.paymentFailed;
    if (payment == null) return RideStatus.tripCompleted;
    if (!payment.isSettled) return RideStatus.paymentProcessing;
    return switch (rating) {
      TripRatingStatus.pending => RideStatus.ratingPending,
      TripRatingStatus.submitted || TripRatingStatus.skipped =>
        RideStatus.closed,
      TripRatingStatus.notRequested || null => RideStatus.paymentFinalized,
    };
  }

  /// Parses a bare status field. A contract snake_case name first; then, for
  /// one migration window, a legacy Rider-shaped [RideStatus] name
  /// (`driverArriving`) from older stored or test payloads. Returns null for
  /// anything else.
  static RideStatus? parse(
    Object? raw, {
    Object? paymentStatus,
    Object? ratingStatus,
  }) {
    if (raw is! String) return null;
    final trip = TripStatusWire.parse(raw);
    if (trip != null) {
      return fromTrip(
        trip,
        paymentStatus: TripPaymentStatusWire.parse(paymentStatus),
        ratingStatus: TripRatingStatusWire.parse(ratingStatus),
      );
    }
    return legacyName(raw);
  }

  /// A [RideStatus] by its Dart name (device-local snapshots and the
  /// pre-v0.3 wire). Not for contract payloads.
  static RideStatus? legacyName(Object? raw) {
    if (raw is! String) return null;
    final name = raw.trim();
    for (final status in RideStatus.values) {
      if (status.name == name) return status;
    }
    return null;
  }

  /// The UI state of a trip projection: `status` plus `paymentStatus` and
  /// `ratingStatus`.
  static RideStatus? fromProjection(Map<dynamic, dynamic> projection) =>
      parse(
        projection['status'],
        paymentStatus: projection['paymentStatus'],
        ratingStatus: projection['ratingStatus'],
      );
}
