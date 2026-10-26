import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/ride_booking/application/ride_restore_coordinator.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// iOS terminates and reloads a standalone web app readily — the system
/// location prompt during Book Now is enough. The rider's ride must outlive
/// that reload, including a Safari tab on the public link.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  RideSnapshot searching() => RideSnapshot(
    status: RideStatus.findingDriver,
    rideId: 'ride_pwa_1',
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

  test('installed app reloaded mid-search comes back to Finding', () async {
    final snapshot = searching();
    final coordinator = RideRestoreCoordinator(
      reader: () async => snapshot,
      skipRestore: () => false, // installed PWA: restore is allowed
    );

    final page = await coordinator.root();

    expect(coordinator.showing, RestoredSurface.finding);
    expect(page, isA<Widget>());
  });

  test('public Safari tab also comes back to Finding', () async {
    final snapshot = searching();
    final coordinator = RideRestoreCoordinator(reader: () async => snapshot);

    final page = await coordinator.root();

    expect(coordinator.showing, RestoredSurface.finding);
    expect(page, isA<Widget>());
    expect(coordinator.takeSearchInterrupted(), isFalse);
  });

  test('non-web builds never report themselves as an installed web app', () {
    expect(RideRestoreCoordinator.defaultSkipRestore(), isFalse);
  });
}
