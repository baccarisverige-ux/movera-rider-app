/// The Rider UI/session enum. It is NOT the wire vocabulary: the server
/// speaks [TripStatus] (snake_case) plus `paymentStatus` / `ratingStatus`
/// fields, and `RideStatusWire.fromProjection` derives one of these from
/// them (contract v0.3.0). Post-trip values (`paymentProcessing`,
/// `paymentFinalized`, `ratingPending`, `paymentFailed`, `closed`) are such
/// derived UI states, not trip statuses.
enum RideStatus {
  idle,
  pickupSelected,
  destinationSelected,
  quoteLoading,
  rideOptionsReady,
  rideSelected,
  paymentSelected,
  bookingRequested,
  findingDriver,
  searchDelayed,
  driverAssigned,
  driverArriving,
  driverWaiting,
  tripStarted,
  tripInProgress,
  approachingDropoff,
  tripCompleted,
  paymentProcessing,
  paymentFinalized,
  ratingPending,
  closed,
  cancelledByRider,

  /// UI notice: the driver dropped the ride before pickup and the server put
  /// the trip back to `searching` (contract `cancel` by driver, live). The
  /// rider keeps the same trip; Waiting says so and the search resumes.
  /// Kept in [RideStatusX.isTerminal] only so the UI stops tracking the old
  /// driver; it is never a terminal status on the wire.
  cancelledByDriver,
  cancelledBySystem,
  noDriverFound,
  paymentFailed,
  bookingExpired,

  /// `cancelled_by_admin`: Movera support cancelled the trip.
  cancelledByAdmin,

  /// `no_show`: the driver waited and the rider never came.
  noShow,

  /// `failed`: the trip broke on the server side (error + support).
  tripFailed,

  /// `cancelled_by_driver`: the driver ended the trip after the rider got
  /// in. Truly terminal. A driver dropping the ride *before* pickup is not
  /// this: the server puts the trip back to `searching` and the UI shows
  /// [cancelledByDriver] as a reassignment notice.
  endedByDriver,
}

extension RideStatusX on RideStatus {
  bool get isTerminal =>
      this == RideStatus.closed ||
      this == RideStatus.cancelledByRider ||
      this == RideStatus.cancelledByDriver ||
      this == RideStatus.cancelledBySystem ||
      this == RideStatus.noDriverFound ||
      this == RideStatus.paymentFailed ||
      this == RideStatus.bookingExpired ||
      this == RideStatus.cancelledByAdmin ||
      this == RideStatus.noShow ||
      this == RideStatus.tripFailed ||
      this == RideStatus.endedByDriver;

  bool get isSearching =>
      this == RideStatus.bookingRequested ||
      this == RideStatus.findingDriver ||
      this == RideStatus.searchDelayed;

  bool get isMatched =>
      this == RideStatus.driverAssigned ||
      this == RideStatus.driverArriving ||
      this == RideStatus.driverWaiting ||
      this == RideStatus.tripStarted ||
      this == RideStatus.tripInProgress ||
      this == RideStatus.approachingDropoff;

  bool get isCompletedSurface =>
      this == RideStatus.tripCompleted ||
      this == RideStatus.paymentProcessing ||
      this == RideStatus.paymentFinalized ||
      this == RideStatus.ratingPending;
}
