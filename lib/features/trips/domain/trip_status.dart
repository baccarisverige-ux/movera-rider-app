import 'package:movera_rider/core/contracts/trip_status.dart' as contract;

export 'package:movera_rider/core/contracts/trip_status.dart'
    show TripStatus, TripStatusWire;

/// Feature-domain helpers kept on the historical import path.
///
/// The enum itself is canonical in core/contracts so Rider, Driver and future
/// Admin-facing adapters cannot silently fork the platform lifecycle.
extension TripStatusX on contract.TripStatus {
  // isTerminal lives on TripStatusWire: the contract terminal set, once.

  bool get isActive =>
      this == contract.TripStatus.requested ||
      this == contract.TripStatus.searching ||
      this == contract.TripStatus.offered ||
      this == contract.TripStatus.accepted ||
      this == contract.TripStatus.driverToPickup ||
      this == contract.TripStatus.arrived ||
      this == contract.TripStatus.riderOnboard ||
      this == contract.TripStatus.inTrip ||
      this == contract.TripStatus.approachingDropoff;
}
