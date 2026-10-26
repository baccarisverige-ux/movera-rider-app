import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/features/ride_booking/application/ride_restore_coordinator.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A cold restore rebuilds the screen but used to leave AppScope's ride empty,
/// so the restored search had no rideId. Cancel then reached no ride and
/// raising the offer refused, both silently.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppScope.instance.ride.rideId = null;
    AppScope.instance.ride.restoreFromBackend(RideStatus.idle);
  });

  RideSnapshot snapshotWith(RideStatus status) => RideSnapshot(
    status: status,
    rideId: 'ride_restored_42',
    pickupAddress: 'Sveavägen 1',
    destinationAddress: 'Hornsgatan 2',
    pickupLat: 59.3400,
    pickupLng: 18.0550,
    destinationLat: 59.3170,
    destinationLng: 18.0450,
    rideType: 'Movera',
    price: 259,
    paymentMethod: 'Apple Pay',
    savedAt: DateTime.now(),
  );

  test('restoring a search adopts the ride id so Cancel has a ride', () {
    RideRestoreCoordinator(
      skipRestore: () => false,
    ).pageFor(snapshotWith(RideStatus.findingDriver));

    expect(AppScope.instance.ride.rideId, 'ride_restored_42');
    expect(AppScope.instance.ride.status, RideStatus.findingDriver);
  });

  test('restoring an assigned ride adopts its id too', () {
    RideRestoreCoordinator(
      skipRestore: () => false,
    ).pageFor(snapshotWith(RideStatus.driverAssigned));

    expect(AppScope.instance.ride.rideId, 'ride_restored_42');
    expect(AppScope.instance.ride.status, RideStatus.driverAssigned);
  });

  test('restoring Home leaves no stale ride identity behind', () {
    RideRestoreCoordinator(skipRestore: () => false).pageFor(null);

    expect(AppScope.instance.ride.rideId, isNull);
  });
}
