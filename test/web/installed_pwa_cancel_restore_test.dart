import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/data/finding_driver_repository.dart';
import 'package:movera_rider/features/ride_booking/application/ride_restore_coordinator.dart';
import 'package:movera_rider/features/ride_booking/application/ride_session.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RideSnapshotStore.epoch = 0;
    FindingDriverController.active = null;
  });

  test('installed PWA reload after rider cancel stays Home', () async {
    const rideId = 'pwa-cancel';
    final snapshot = RideSnapshot(
      status: RideStatus.findingDriver,
      savedAt: DateTime.now(),
      pickupAddress: 'Pickup',
      destinationAddress: 'Destination',
      pickupLat: 59.33,
      pickupLng: 18.06,
      destinationLat: 59.32,
      destinationLng: 18.07,
      rideType: 'Movera',
      price: 259,
      paymentMethod: 'Apple Pay',
      rideId: rideId,
    );
    final store = FindingDriverRepository();
    await store.save(snapshot);
    final realtime = MockRideRealtime(assignAfter: const Duration(days: 1));
    final ride = RideSession()..rideId = rideId;
    final controller = FindingDriverController(
      realtime: realtime,
      ride: ride,
      store: store,
    );

    controller.start(snapshot: snapshot, onTick: (_) {}, onMatched: () {});
    await controller.cancelSearch(reasonId: 'plans_changed');

    expect(ride.status, RideStatus.cancelledByRider);
    expect(ride.suppressRestore, isTrue);
    expect(await RideSnapshotStore.read(), isNull);

    final coordinator = RideRestoreCoordinator(
      reader: RideSnapshotStore.read,
      skipRestore: () => false, // installed PWA can normally restore rides
    );
    await coordinator.root();

    expect(coordinator.showing, RestoredSurface.home);

    controller.dispose();
    realtime.dispose();
  });
}
