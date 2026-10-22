import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/config/zone_clock.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/application/scheduled_ride_checkout.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/presentation/reservation_format.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/ride_selection/application/scheduled_ride_booking.dart';
import 'package:movera_rider/features/ride_selection/domain/booking_mode.dart';
import 'package:movera_rider/features/scheduled_rides/application/stockholm_schedule.dart';

import 'scheduled_quote_harness.dart';

/// rider-63: a Book-later time is the pickup zone's wall-clock time (Q9),
/// but the reservation stored it as a device-local time and compared it
/// with the device clock. On a device outside the pickup zone (UTC, New
/// York) the countdown, T-2 start, no-driver timeout and cancel window
/// were all off by the zone difference. Runs the same in every TZ.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 10:00 UTC on 21 Oct 2026: 12:00 in Stockholm (summer time).
  final now = DateTime.utc(2026, 10, 21, 10);
  const stockholmPickup = ReservationPlace(
    label: 'Klockarvägen 37',
    lat: 59.3293,
    lng: 18.0686,
  );
  const destination = ReservationPlace(
    label: 'Arlanda Express',
    lat: 59.6497,
    lng: 17.9237,
  );

  ReservationController reservations() => ReservationController(
    store: LocalReservationRepository(storage: MemoryReservationStorage()),
    clock: () => now,
  );

  RideSelectionController pickedAt(DateTime wall) {
    final selection = RideSelectionController(
      bookingMode: BookingMode.scheduled,
    );
    addTearDown(selection.dispose);
    final ride = selection.rideById('economy');
    selection.selectRide(ride.id, ride.price);
    selection.scheduleFor(wall);
    adoptScheduledQuote(selection, 'economy');
    return selection;
  }

  test('the earliest pickup is 30 minutes away on any device', () async {
    final wall = PickupSchedule.stockholm.minimumPickup(now);
    expect(ReservationFormat.time(wall), '12:30');
    final c = reservations();
    final ride = await ScheduledRideBooking.confirm(
      reservations: c,
      selection: pickedAt(wall),
      pickup: stockholmPickup,
      destination: destination,
    );

    expect(ride.scheduledPickupAt.difference(now), const Duration(minutes: 30));
    expect(ride.timeZone, ZoneClock.stockholm);
    // Every screen still shows the Stockholm time the rider picked.
    expect(ReservationFormat.time(ride.pickupWallTime), '12:30');
    expect(
      ReservationFormat.time(ride.dropoffWallTime!),
      ReservationFormat.time(
        wall.add(ride.estimatedDropoffAt!.difference(ride.scheduledPickupAt)),
      ),
    );

    // T-2 has not come yet 20 minutes before the real pickup...
    await c.startLiveIfDue(now: now.add(const Duration(minutes: 10)));
    expect(c.byId(ride.reservationId)!.status.name, 'scheduled');
    // ... and a ride 30 minutes away is not "No driver found".
    expect(c.isNoDriverFound(ride, now: now), isFalse);
    expect(
      c.isNoDriverFound(ride, now: now.add(const Duration(minutes: 36))),
      isTrue,
    );
  });

  test('the review draft shows the picked zone time too', () {
    final wall = DateTime.utc(2026, 10, 22, 7, 15);
    final draft = ScheduledRideCheckout.draftFrom(
      selection: pickedAt(wall),
      pickup: stockholmPickup,
      destination: destination,
    );
    expect(
      draft.scheduledPickupAt.isAtSameMomentAs(
        DateTime.utc(2026, 10, 22, 5, 15),
      ),
      isTrue,
    );
    expect(draft.pickupWallTime, wall);
  });

  test('a ride stored and read back keeps its zone and time', () async {
    final wall = DateTime.utc(2026, 10, 22, 7, 15);
    final c = reservations();
    final ride = await ScheduledRideBooking.confirm(
      reservations: c,
      selection: pickedAt(wall),
      pickup: stockholmPickup,
      destination: destination,
    );
    final back = Reservation.tryParse(ride.toJson())!;
    expect(back.timeZone, ZoneClock.stockholm);
    expect(back.pickupWallTime, wall);
    expect(
      back.scheduledPickupAt.isAtSameMomentAs(ride.scheduledPickupAt),
      isTrue,
    );
  });
}
