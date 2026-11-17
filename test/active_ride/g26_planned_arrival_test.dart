import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/active_ride/presentation/trip_arrival.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride_geometry.dart';

/// G26 / G-S6 (owner 2026-11-17): at trip start the title jumped "Ride in
/// progress" -> "Arrive by 08:21" when the first live ETA came
/// (waiting_for_driver_sheet.dart _tripHeadline returned null without one).
/// Owner: show the PLANNED arrival time until the live one arrives.
void main() {
  const pickup = GeoPoint(36.8065, 10.1815);
  const drop = GeoPoint(36.8380, 10.2400);
  final start = DateTime(2026, 11, 17, 8, 0);

  test('in trip without a live ETA: the planned arrival time', () {
    final at = tripArrivalAt(
      status: RideStatus.tripStarted,
      liveSeconds: null,
      plannedFrom: start,
      pickup: pickup,
      stops: const [],
      destination: drop,
      now: start,
    );
    expect(
      at,
      start.add(
        Duration(minutes: estimatedRouteMinutes(pickup, const [], drop)),
      ),
    );
  });

  test('the live ETA replaces the plan', () {
    final now = start.add(const Duration(minutes: 1));
    final at = tripArrivalAt(
      status: RideStatus.tripInProgress,
      liveSeconds: 600,
      plannedFrom: start,
      pickup: pickup,
      stops: const [],
      destination: drop,
      now: now,
    );
    expect(at, now.add(const Duration(seconds: 600)));
  });

  test('not in trip: no arrival time', () {
    expect(
      tripArrivalAt(
        status: RideStatus.driverAssigned,
        liveSeconds: null,
        plannedFrom: start,
        pickup: pickup,
        stops: const [],
        destination: drop,
        now: start,
      ),
      isNull,
    );
  });

  test('a 2-stop trip does not show the no-stops time (stops counted)', () {
    const stops = [GeoPoint(36.8600, 10.1500), GeoPoint(36.7900, 10.2800)];
    DateTime? at(List<GeoPoint> s) => tripArrivalAt(
      status: RideStatus.tripStarted,
      liveSeconds: null,
      plannedFrom: start,
      pickup: pickup,
      stops: s,
      destination: drop,
      now: start,
    );
    expect(at(stops)!.isAfter(at(const [])!), isTrue);
    expect(
      at(stops),
      start.add(Duration(minutes: estimatedRouteMinutes(pickup, stops, drop))),
    );
  });
}
