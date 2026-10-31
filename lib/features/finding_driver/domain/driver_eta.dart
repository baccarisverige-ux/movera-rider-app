import 'package:movera_rider/core/contracts/trip_eta.dart';
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
    this.server,
    this.freshAt,
  });

  final int? seconds;
  final double? distanceMeters;
  final DateTime? locationAt;
  final double? latitude;
  final double? longitude;
  final bool stale;

  /// Contract v0.18.7 (Q4, status item 2): the server's road-route ETA
  /// (every 30 s), when the trip has one. [seconds] and [distanceMeters]
  /// are its numbers then; the app computes nothing itself.
  final TripEta? server;

  /// The newest server stamp about the driver, on the device clock: the
  /// fix time or the ETA tick, whichever is later. Staleness is judged on
  /// it, so a parked driver whose phone sends few fixes is not "updating
  /// location" while the server still ticks the ETA (owner bug: "waiting
  /// for new position" while the driver is parked).
  final DateTime? freshAt;

  /// `pickupWaiting.eta.staleAfterSeconds`: an ETA older than this is the
  /// estimate; the screen says it is updating. Was 25 s before v0.18.7,
  /// which flagged a parked driver's rarer fixes as a lost connection.
  static const staleAfter = Duration(seconds: 120);

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
    TripEta? server,
    DateTime? serverEtaAt,
  }) {
    final clock = now ?? DateTime.now();
    // Once the trip is under way, "how far / how long" means distance to
    // drop-off, not the pickup point the driver already reached.
    final useDestination =
        status != null &&
        isInTrip(status) &&
        destinationLat != null &&
        destinationLng != null;
    final straight = metersBetween(
      latitude,
      longitude,
      useDestination ? destinationLat : pickupLat,
      useDestination ? destinationLng : pickupLng,
    );
    final freshAt = serverEtaAt != null && serverEtaAt.isAfter(locationAt)
        ? serverEtaAt
        : locationAt;
    // Checker round 1: `source: stale` = the server has had no driver
    // position for 2 min and kept the last ETA; the screen says so.
    final stale =
        clock.difference(freshAt) > staleAfter || server?.source == 'stale';
    // The server's road ETA first (both apps show the same one), its
    // `etaSeconds` repeat next, the straight-line guess only without any.
    final seconds =
        server?.etaSeconds ?? etaSeconds ?? secondsForDistance(straight);
    return DriverEta(
      seconds: seconds,
      distanceMeters: server?.distanceMeters.toDouble() ?? straight,
      locationAt: locationAt,
      latitude: latitude,
      longitude: longitude,
      stale: stale,
      server: server,
      freshAt: freshAt,
    );
  }

  /// Recomputes staleness only, keeping every other field. Used by a
  /// standing timer so a marker whose updates stopped arriving is caught
  /// even though no new fix ever triggers [fromFix] again.
  DriverEta withStalenessCheckedAt(DateTime now) {
    final at = freshAt ?? locationAt;
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
      server: server,
      freshAt: freshAt,
    );
  }

  /// The road distance as the owner wants it shown (`distanceDisplay`),
  /// only when the server routed it; null for a straight-line guess.
  String? distanceText() {
    final routed = server;
    if (routed == null) return null;
    return EtaDistance.of(routed.distanceMeters).format(L10n.code);
  }

  /// "Arrives in 4 min · 1,2 km" (driver coming) / "There in 12 min ·
  /// 3,4 km" (on board), from the server ETA; null without one.
  String? routedLine({RideStatus status = RideStatus.driverAssigned}) {
    final routed = server;
    final distance = distanceText();
    if (routed == null || distance == null) return null;
    final minutes = '${routed.minutes}';
    return isInTrip(status) || !routed.toPickup
        ? L10n.current.etaThereIn(minutes, distance)
        : L10n.current.etaArrivesIn(minutes, distance);
  }

  String headline({RideStatus status = RideStatus.driverAssigned}) {
    if (isInTrip(status)) {
      return L10n.current.etaRideInProgress;
    }
    if (status == RideStatus.driverWaiting) {
      return L10n.current.etaDriverArrived;
    }
    if (stale) return L10n.current.etaUpdatingLocation;
    final routed = routedLine(status: status);
    if (routed != null) return routed;
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
      final routed = routedLine(status: status);
      if (routed != null && !stale) return routed;
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
