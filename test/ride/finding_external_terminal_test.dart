import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/data/finding_driver_repository.dart';
import 'package:movera_rider/features/history/data/on_demand_ride_history_store.dart';
import 'package:movera_rider/features/ride_booking/application/ride_session.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

RideSnapshot _snapshot() => RideSnapshot(
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
  rideId: 'external-terminal-ride',
);

FindingDriverController _controller(
  MockRideRealtime realtime,
  RideSession ride,
) {
  return FindingDriverController(
    realtime: realtime,
    ride: ride,
    store: FindingDriverRepository(),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RideSnapshotStore.epoch = 0;
  });

  test('no-driver event ends Finding and clears the active snapshot', () async {
    final realtime = MockRideRealtime(assignAfter: const Duration(days: 1));
    addTearDown(realtime.dispose);
    final ride = RideSession()..rideId = 'external-terminal-ride';
    final snapshot = _snapshot();
    await RideSnapshotStore.save(snapshot);

    final controller = _controller(realtime, ride);
    addTearDown(controller.dispose);
    controller.start(snapshot: snapshot, onTick: (_) {}, onMatched: () {});

    realtime.emit(RideStatus.noDriverFound, sequence: 4);
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(ride.status, RideStatus.noDriverFound);
    expect(controller.matchCount, 0);
    expect(await RideSnapshotStore.read(), isNull);
  });

  // Audit 2026-10-21 (rider-32): a driver drop is a reversible dispatch
  // event (contract §3: the trip is back in `searching`), never the end of
  // the ride. This test used to expect the search to file the ride as
  // cancelled and clear the snapshot; that was the bug.
  test('driver cancellation during search keeps the search going', () async {
    final realtime = MockRideRealtime(assignAfter: const Duration(days: 1));
    addTearDown(realtime.dispose);
    final ride = RideSession()..rideId = 'external-terminal-ride';
    final snapshot = _snapshot();
    await RideSnapshotStore.save(snapshot);

    final controller = _controller(realtime, ride);
    addTearDown(controller.dispose);
    var matched = 0;
    controller.start(
      snapshot: snapshot,
      onTick: (_) {},
      onMatched: () => matched += 1,
    );

    realtime.emit(RideStatus.cancelledByDriver, sequence: 5);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(ride.status, RideStatus.findingDriver);
    expect(await RideSnapshotStore.read(), isNotNull);
    expect(await OnDemandRideHistoryStore.read(), isEmpty);
    expect(identical(FindingDriverController.active, controller), isTrue);

    // The next driver's acceptance still reaches the search (the mock's own
    // re-opened search took sequence 6).
    realtime.emit(RideStatus.driverAssigned);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(matched, 1);
  });
}
