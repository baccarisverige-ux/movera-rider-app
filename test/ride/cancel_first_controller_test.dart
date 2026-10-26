import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/data/finding_driver_repository.dart';
import 'package:movera_rider/features/ride_booking/application/ride_restore_coordinator.dart';
import 'package:movera_rider/features/ride_booking/application/ride_session.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

RideSnapshot snap() => RideSnapshot(
  status: RideStatus.findingDriver,
  savedAt: DateTime.now(),
  pickupAddress: 'A',
  destinationAddress: 'B',
  pickupLat: 59.3,
  pickupLng: 18.0,
  destinationLat: 59.4,
  destinationLng: 18.1,
  rideType: 'Movera',
  price: 259,
  paymentMethod: 'Apple Pay',
  rideId: 'r1',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RideSnapshotStore.epoch = 0;
    FindingDriverController.active = null;
  });

  test('keep-after-confirm stays cancelled (cancel-first)', () async {
    final rt = MockRideRealtime(assignAfter: const Duration(days: 1));
    final ride = RideSession()..rideId = 'r1';
    var matches = 0;
    final controller = FindingDriverController(
      realtime: rt,
      ride: ride,
      store: FindingDriverRepository(),
    );
    controller.start(
      snapshot: snap(),
      onTick: (_) {},
      onMatched: () => matches += 1,
    );
    await controller.cancelSearch();
    expect(ride.status, RideStatus.cancelledByRider);
    expect(ride.suppressRestore, isTrue);
    expect(await RideSnapshotStore.read(), isNull);
    rt.emit(RideStatus.driverAssigned, sequence: 11);
    rt.assignNow();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(matches, 0);
    expect(controller.matchCount, 0);
    expect(await RideSnapshotStore.read(), isNull);
    controller.dispose();
    rt.dispose();
  });

  test('assign-during-why cannot restore Finding', () async {
    final rt = MockRideRealtime(assignAfter: const Duration(days: 1));
    final ride = RideSession()..rideId = 'r1';
    var matches = 0;
    final store = FindingDriverRepository();
    await store.save(snap());
    final controller = FindingDriverController(
      realtime: rt,
      ride: ride,
      store: store,
    );
    controller.start(
      snapshot: snap(),
      onTick: (_) {},
      onMatched: () => matches += 1,
    );
    await controller.cancelSearch(reasonId: 'plans_changed');
    expect(ride.suppressRestore, isTrue);
    rt.assignNow();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(matches, 0);
    expect(controller.matchCount, 0);
    controller.dispose();
    rt.dispose();
  });

  test('restore-during-why cannot restore Finding', () async {
    final rt = MockRideRealtime(assignAfter: const Duration(days: 1));
    final ride = RideSession()..rideId = 'r1';
    final controller = FindingDriverController(
      realtime: rt,
      ride: ride,
      store: FindingDriverRepository(),
    );
    controller.start(snapshot: snap(), onTick: (_) {}, onMatched: () {});
    await controller.cancelSearch();
    expect(await RideSnapshotStore.read(), isNull);
    expect(ride.suppressRestore, isTrue);
    final restore = RideRestoreCoordinator(reader: RideSnapshotStore.read);
    expect(
      restore.surfaceFor(await RideSnapshotStore.read()),
      RestoredSurface.home,
    );
    expect(await restore.resumeIfNeeded(), isNull);
    controller.dispose();
    rt.dispose();
  });
}
