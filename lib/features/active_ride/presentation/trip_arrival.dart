import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/finding_driver/domain/driver_eta.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride_geometry.dart';

/// The arrival time the trip sheet shows ("Arrive by HH:MM"), or null
/// before the trip starts.
///
/// G26 / G-S6 (owner 2026-11-17): the live server ETA when there is one;
/// until the first one arrives, the PLANNED time (the same route estimate
/// the vehicle list showed at booking) counted from [plannedFrom], the
/// moment the trip started, so the title never jumps from "Ride in
/// progress" to a time.
DateTime? tripArrivalAt({
  required RideStatus status,
  required int? liveSeconds,
  required DateTime plannedFrom,
  required GeoPoint pickup,
  required List<GeoPoint> stops,
  required GeoPoint destination,
  required DateTime now,
}) {
  if (!DriverEta.isInTrip(status)) return null;
  if (liveSeconds != null) return now.add(Duration(seconds: liveSeconds));
  return plannedFrom.add(
    Duration(minutes: estimatedRouteMinutes(pickup, stops, destination)),
  );
}
