import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/ride_booking/application/ride_restore_coordinator.dart';
import 'package:movera_rider/features/ride_booking/data/driver_repository.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/matched_driver.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_complete/data/last_completed_ride.dart';

RideSnapshot completedSnapshot({RideStatus status = RideStatus.ratingPending}) {
  return RideSnapshot(
    status: status,
    savedAt: DateTime.now(),
    pickupAddress: 'Pickup Street 1',
    destinationAddress: 'Destination Street 9',
    pickupLat: 59.33,
    pickupLng: 18.06,
    destinationLat: 59.34,
    destinationLng: 18.07,
    rideType: 'Movera XL',
    price: 399,
    paymentMethod: 'Apple Pay',
    rideId: 'ride-completed-25',
    driver: const MatchedDriver(
      id: 'driver-1',
      firstName: 'Sara',
      rating: 4.9,
      tripCount: 1200,
      vehicleMake: 'Volvo',
      vehicleModel: 'EX40',
      vehicleColor: 'Black',
      plate: 'ABC123',
    ),
  );
}

void main() {
  tearDown(LastCompletedRide.clear);

  test('cold completion restore repopulates completed ride context', () {
    final snapshot = completedSnapshot();
    final coordinator = RideRestoreCoordinator();

    expect(LastCompletedRide.value, isNull);
    final page = coordinator.pageFor(snapshot);

    expect(page.runtimeType.toString(), 'RideCompleted');
    expect(LastCompletedRide.value?.rideId, 'ride-completed-25');
    expect(LastCompletedRide.value?.driver?.firstName, 'Sara');

    final driver = const DriverRepository().current();
    final receipt = const TripReceiptRepository().last();
    expect(driver?.name, 'Sara');
    expect(driver?.vehicle, 'Black Volvo EX40');
    expect(receipt?.pickup, 'Pickup Street 1');
    expect(receipt?.destination, 'Destination Street 9');
    expect(receipt?.total, '399 kr');
    expect(receipt?.method, 'Apple Pay');
    expect(receipt?.isFinal, isFalse);
  });

  test('all restorable completion statuses reopen completion surface', () {
    final coordinator = RideRestoreCoordinator();

    for (final status in <RideStatus>[
      RideStatus.tripCompleted,
      RideStatus.paymentProcessing,
      RideStatus.paymentFinalized,
      RideStatus.ratingPending,
    ]) {
      final snapshot = completedSnapshot(status: status);
      expect(coordinator.surfaceFor(snapshot), RestoredSurface.complete);
    }
  });
}
