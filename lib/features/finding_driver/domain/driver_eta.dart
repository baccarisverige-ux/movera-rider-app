import 'package:movera_rider/core/maps/geo_distance.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/l10n/l10n.dart';

class DriverEta {
  const DriverEta({
    this.seconds,
    this.distanceMeters,
    this.locationAt,
    this.latitude,
    this.longitude,
    this.stale = false,
  });

  final int? seconds;
  final double? distanceMeters;
  final DateTime? locationAt;
  final double? latitude;
  final double? longitude;
  final bool stale;

  static const staleAfter = Duration(seconds: 25);

  /// Every stage the driver marker/ETA must treat as "en route to drop-off"
  /// rather than "en route to pickup". `approachingDropoff` was previously
  /// missed by callers that only checked tripStarted/tripInProgress.
  static bool isInTrip(RideStatus status) =>
      status == RideStatus.tripStarted ||
      status == RideStatus.tripInProgress ||
      status == RideStatus.approachingDropoff;

  static double metersBetween(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) => GeoDistance.metersBetween(lat1, lng1, lat2, lng2);

  static int secondsForDistance(double meters) =>
      GeoDistance.urbanSecondsForDistance(meters);

  factory DriverEta.fromFix({
    required double latitude,
    required double longitude,
    required double pickupLat,
    required double pickupLng,
    required DateTime locationAt,
    double? destinationLat,
    double? destinationLng,
    int? etaSeconds,
    DateTime? now,
    RideStatus? status,
  }) {
    final clock = now ?? DateTime.now();
    // Once the trip is under way, "how far / how long" means distance to
    // drop-off, not the pickup point the driver already reached.
    final useDestination =
        status != null &&
        isInTrip(status) &&
        destinationLat != null &&
        destinationLng != null;
    final distance = metersBetween(
      latitude,
      longitude,
      useDestination ? destinationLat : pickupLat,
      useDestination ? destinationLng : pickupLng,
    );
    final stale = clock.difference(locationAt) > staleAfter;
    final seconds = etaSeconds ?? secondsForDistance(distance);
    return DriverEta(
      seconds: seconds,
      distanceMeters: distance,
      locationAt: locationAt,
      latitude: latitude,
      longitude: longitude,
      stale: stale,
    );
  }

  /// Recomputes staleness only, keeping every other field. Used by a
  /// standing timer so a marker whose updates stopped arriving is caught
  /// even though no new fix ever triggers [fromFix] again.
  DriverEta withStalenessCheckedAt(DateTime now) {
    final at = locationAt;
    if (at == null) return this;
    final isStale = now.difference(at) > staleAfter;
    if (isStale == stale) return this;
    return DriverEta(
      seconds: seconds,
      distanceMeters: distanceMeters,
      locationAt: locationAt,
      latitude: latitude,
      longitude: longitude,
      stale: isStale,
    );
  }

  String headline({RideStatus status = RideStatus.driverAssigned}) {
    if (isInTrip(status)) {
      return L10n.current.etaRideInProgress;
    }
    if (status == RideStatus.driverWaiting) {
      return L10n.current.etaDriverArrived;
    }
    if (stale) return L10n.current.etaUpdatingLocation;
    final distance = distanceMeters;
    if (distance != null && distance < 180) return L10n.current.etaAlmostThere;
    final eta = seconds;
    if (eta == null) return L10n.current.etaOnTheWay;
    if (eta < 60) return L10n.current.etaAlmostThere;
    final minutes = (eta / 60).ceil();
    return L10n.current.etaPickupInMin('$minutes');
  }

  String? subtitle({
    String? firstName,
    RideStatus status = RideStatus.driverAssigned,
  }) {
    if (isInTrip(status)) {
      return firstName == null
          ? L10n.current.etaToDropoff
          : L10n.current.etaNameToDropoff(firstName);
    }
    if (stale) return L10n.current.etaWaitingFreshLocation;
    if (status == RideStatus.driverWaiting) {
      return firstName == null
          ? L10n.current.etaDriverAtPickup
          : L10n.current.etaNameAtPickup(firstName);
    }
    if (firstName == null || firstName.isEmpty) {
      return L10n.current.etaLeaveNow;
    }
    return L10n.current.etaLeaveNowName(firstName);
  }
}
