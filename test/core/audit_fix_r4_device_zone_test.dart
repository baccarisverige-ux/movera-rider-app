import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/ride_booking/data/driver_repository.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/matched_driver.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_complete/data/last_completed_ride.dart';

/// Audit round 4: times shown in the device zone. Only bites where the
/// device zone is not UTC: Architecture gates also runs this file with
/// TZ=Europe/Stockholm and TZ=America/New_York.
void main() {
  tearDown(LastCompletedRide.clear);

  test('rider-r4-8: the completion "Date and time" of a stored snapshot is '
      'the local time, not UTC', () {
    final saved = RideSnapshot(
      status: RideStatus.tripCompleted,
      rideId: 'ride_r4_8',
      pickupAddress: 'A',
      destinationAddress: 'B',
      pickupLat: 59.34,
      pickupLng: 18.05,
      destinationLat: 59.31,
      destinationLng: 18.04,
      rideType: 'Movera',
      price: 259,
      paymentMethod: 'Card',
      savedAt: DateTime(2026, 1, 5, 0, 30),
      driver: const MatchedDriver(id: 'drv_1', firstName: 'Elin'),
    );
    // A reload or an ended-early receipt reads the snapshot back from the
    // store, where savedAt is UTC.
    LastCompletedRide.remember(RideSnapshot.fromJson(saved.toJson()));

    expect(
      const DriverRepository().current(rideId: 'ride_r4_8')!.completedAt,
      '5 Jan 2026, 00:30',
    );
  });
}
