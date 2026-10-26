import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/data/finding_driver_repository.dart';
import 'package:movera_rider/features/ride_booking/application/ride_session.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

RideSnapshot _snapshot(String id) => RideSnapshot(
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
  rideId: id,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RideSnapshotStore.epoch = 0;
    FindingDriverController.active = null;
  });

  test(
    'driver assignment enters matched state exactly once with same ride id',
    () async {
      const rideId = 'match-once';
      final realtime = MockRideRealtime(assignAfter: const Duration(days: 1));
      final ride = RideSession()..rideId = rideId;
      final store = FindingDriverRepository();
      final controller = FindingDriverController(
        realtime: realtime,
        ride: ride,
        store: store,
      );
      var matches = 0;

      controller.start(
        snapshot: _snapshot(rideId),
        onTick: (_) {},
        onMatched: () => matches += 1,
      );

      realtime.emit(RideStatus.driverAssigned, sequence: 2);
      realtime.emit(RideStatus.driverAssigned, sequence: 3);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(matches, 1);
      expect(controller.matchCount, 1);
      expect(ride.rideId, rideId);
      expect(ride.status, RideStatus.driverAssigned);
      final stored = await RideSnapshotStore.read();
      expect(stored?.rideId, rideId);
      expect(stored?.status, RideStatus.driverAssigned);

      controller.dispose();
      realtime.dispose();
    },
  );

  test(
    'cancel is idempotent and a late assignment cannot resurrect the ride',
    () async {
      const rideId = 'cancel-twice';
      final realtime = MockRideRealtime(assignAfter: const Duration(days: 1));
      final ride = RideSession()..rideId = rideId;
      final store = FindingDriverRepository();
      await store.save(_snapshot(rideId));
      final controller = FindingDriverController(
        realtime: realtime,
        ride: ride,
        store: store,
      );
      var matches = 0;

      controller.start(
        snapshot: _snapshot(rideId),
        onTick: (_) {},
        onMatched: () => matches += 1,
      );

      await controller.cancelSearch(reasonId: 'plans_changed');
      await controller.cancelSearch(reasonId: 'plans_changed');
      realtime.emit(RideStatus.driverAssigned, sequence: 99);
      realtime.assignNow();
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(ride.status, RideStatus.cancelledByRider);
      expect(ride.suppressRestore, isTrue);
      expect(controller.matchCount, 0);
      expect(matches, 0);
      expect(await RideSnapshotStore.read(), isNull);

      controller.dispose();
      realtime.dispose();
    },
  );
}
