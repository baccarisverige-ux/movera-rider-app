import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/ride_selection/application/scheduled_ride_booking.dart';
import 'package:movera_rider/features/scheduled_rides/application/stockholm_schedule.dart';

void main() {
  test('rider-r5-7: in the repeated hour of the fall-back night the '
      'earliest pickup is booked in the hour still to come', () {
    // 02:10 CET, the second 02:00 hour of 25 Oct 2026.
    final now = DateTime.utc(2026, 10, 25, 1, 10);
    StockholmSchedule.clock = () => now;
    addTearDown(() => StockholmSchedule.clock = DateTime.now);
    final pick = PickupSchedule.stockholm.minimumPickup(now);
    expect(pick, DateTime.utc(2026, 10, 25, 2, 40));
    final booked = ScheduledRideBooking.pickupInstant(pick, 'Europe/Stockholm');
    expect(booked, DateTime.utc(2026, 10, 25, 1, 40));
    expect(PickupSchedule.stockholm.toUtc(pick), booked);
  });
}
