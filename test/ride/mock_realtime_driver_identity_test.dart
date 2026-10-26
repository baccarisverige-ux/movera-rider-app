// The mock matching service is a stand-in backend, so it answers with a
// matched driver the way the real service will. The rule it must still obey is
// that the driver comes from behind the API boundary and never from a screen,
// and that the demo identities deleted from this codebase stay deleted.
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/matched_driver.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';

void main() {
  test('mock assignment supplies the matched driver', () async {
    final realtime = MockRideRealtime(assignAfter: const Duration(hours: 1));
    addTearDown(realtime.dispose);

    final events = realtime.subscribe('ride-with-matched-driver');
    final assigned = events.firstWhere(
      (event) => event.status == RideStatus.driverAssigned,
    );

    realtime.assignNow();
    final event = await assigned;

    expect(event.status, RideStatus.driverAssigned);
    expect(realtime.lastDriver, isNotNull);
    expect(realtime.lastDriver!.firstName, isNotEmpty);
  });

  test('the matched driver is never a removed demo identity', () async {
    for (final rideId in ['ride-a', 'ride-b', 'ride-c', 'ride-d']) {
      final realtime = MockRideRealtime(assignAfter: const Duration(hours: 1));
      realtime.subscribe(rideId);
      realtime.assignNow();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final driver = realtime.lastDriver;
      expect(driver, isNotNull);
      expect(driver!.firstName, isNot('Linnea'));
      expect(driver.firstName, isNot('Merle'));
      expect(driver.plate, isNot('MVR 418'));
      realtime.dispose();
    }
  });

  test(
    'explicit real driver payload still passes through realtime unchanged',
    () async {
      final realtime = MockRideRealtime(assignAfter: const Duration(hours: 1));
      addTearDown(realtime.dispose);

      const driver = MatchedDriver(
        id: 'driver-real-123',
        firstName: 'Real driver',
        rating: 4.8,
        tripCount: 321,
        vehicleMake: 'Vehicle make',
        vehicleModel: 'Vehicle model',
        vehicleColor: 'Vehicle color',
        plate: 'REAL 123',
      );

      final events = realtime.subscribe('ride-with-real-driver');
      final matched = events.firstWhere(
        (event) =>
            event.status == RideStatus.driverAssigned && event.driver != null,
      );

      realtime.emit(RideStatus.driverAssigned, driver: driver);
      final event = await matched;

      expect(event.driver?.id, driver.id);
      expect(event.driver?.firstName, driver.firstName);
      expect(event.driver?.rating, driver.rating);
      expect(event.driver?.tripCount, driver.tripCount);
      expect(event.driver?.vehicleLabel, driver.vehicleLabel);
      expect(event.driver?.plate, driver.plate);
    },
  );
}
