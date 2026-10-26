import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/ride_booking/application/ride_restore_coordinator.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

RideSnapshot snapshotWith(RideStatus status) {
  return RideSnapshot(
    rideId: 'ride_interrupted',
    status: status,
    pickupAddress: 'Klockarvägen 37',
    destinationAddress: 'T-Centralen',
    pickupLat: 59.19,
    pickupLng: 17.62,
    destinationLat: 59.33,
    destinationLng: 18.06,
    rideType: 'Movera',
    price: 259,
    paymentMethod: 'Cash',
    savedAt: DateTime.now(),
  );
}

RideRestoreCoordinator coordinatorFor(RideSnapshot? snapshot) {
  return RideRestoreCoordinator(
    reader: () async => snapshot,
    skipRestore: () => true, // the public web build never resumes a search
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('a dropped search is reported once', () async {
    final coordinator = coordinatorFor(snapshotWith(RideStatus.findingDriver));

    await coordinator.root();

    expect(coordinator.takeSearchInterrupted(), isTrue);
    // Reported once only: Home must not keep repeating it.
    expect(coordinator.takeSearchInterrupted(), isFalse);
  });

  test('a delayed search counts as interrupted too', () async {
    final coordinator = coordinatorFor(snapshotWith(RideStatus.searchDelayed));

    await coordinator.root();

    expect(coordinator.takeSearchInterrupted(), isTrue);
  });

  test('an assigned driver counts as interrupted', () async {
    final coordinator = coordinatorFor(snapshotWith(RideStatus.driverAssigned));

    await coordinator.root();

    expect(coordinator.takeSearchInterrupted(), isTrue);
  });

  test('a cold boot with no ride says nothing', () async {
    final coordinator = coordinatorFor(null);

    await coordinator.root();

    expect(coordinator.takeSearchInterrupted(), isFalse);
  });

  test('a finished ride is not an interrupted search', () async {
    final coordinator = coordinatorFor(snapshotWith(RideStatus.tripCompleted));

    await coordinator.root();

    expect(coordinator.takeSearchInterrupted(), isFalse);
  });
}
