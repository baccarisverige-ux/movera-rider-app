import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/features/active_ride/application/active_ride_controller.dart';
import 'package:movera_rider/features/history/data/on_demand_ride_history_store.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RideSnapshotStore.epoch = 0;
    AppScope.instance.ride
      ..rideId = null
      ..status = RideStatus.idle;
  });

  RideSnapshot activeSnapshot() {
    return RideSnapshot(
      status: RideStatus.tripInProgress,
      savedAt: DateTime.now(),
      pickupAddress: 'Current location',
      destinationAddress: 'Stockholm Central Station',
      pickupLat: 59.3293,
      pickupLng: 18.0686,
      destinationLat: 59.3301,
      destinationLng: 18.058,
      rideType: 'Movera',
      price: 259,
      paymentMethod: 'Apple Pay',
      rideId: 'ride-complete-test',
    );
  }

  test(
    'markCompleted keeps a restorable completion snapshot until Done',
    () async {
      final snapshot = activeSnapshot();
      await RideSnapshotStore.save(snapshot);
      AppScope.instance.ride
        ..rideId = snapshot.rideId
        ..status = RideStatus.tripInProgress;

      await ActiveRideController().markCompleted(RideStatus.tripCompleted);

      expect(AppScope.instance.ride.status, RideStatus.tripCompleted);
      final stored = await RideSnapshotStore.read();
      expect(stored, isNotNull);
      expect(stored!.status, RideStatus.tripCompleted);
      expect(stored.rideId, snapshot.rideId);
    },
  );

  test('persistCompletedStatus advances the saved completion state', () async {
    final snapshot = activeSnapshot();
    await RideSnapshotStore.save(snapshot);
    AppScope.instance.ride
      ..rideId = snapshot.rideId
      ..status = RideStatus.tripInProgress;

    final controller = ActiveRideController();
    await controller.markCompleted(RideStatus.tripCompleted);
    await controller.persistCompletedStatus(
      RideStatus.ratingPending,
      rideId: snapshot.rideId!,
    );

    final stored = await RideSnapshotStore.read();
    expect(stored, isNotNull);
    expect(stored!.status, RideStatus.ratingPending);
  });

  test('Done closes the ride and clears the completion snapshot', () async {
    final snapshot = activeSnapshot();
    await RideSnapshotStore.save(snapshot);
    AppScope.instance.ride
      ..rideId = snapshot.rideId
      ..status = RideStatus.tripInProgress;

    final controller = ActiveRideController();
    await controller.markCompleted(RideStatus.ratingPending);
    expect(await RideSnapshotStore.read(), isNotNull);

    controller.markClosed();
    await Future<void>.delayed(Duration.zero);

    expect(AppScope.instance.ride.status, RideStatus.closed);
    expect(await RideSnapshotStore.read(), isNull);
  });

  test(
    'completion close restores missing History before clearing the snapshot',
    () async {
      final snapshot = activeSnapshot();
      await RideSnapshotStore.save(snapshot);
      AppScope.instance.ride
        ..rideId = snapshot.rideId
        ..status = RideStatus.tripInProgress;
      final controller = ActiveRideController();
      await controller.markCompleted(RideStatus.ratingPending);
      await OnDemandRideHistoryStore.clear();

      await controller.closeCompletedRide(snapshot.rideId!);

      expect(await RideSnapshotStore.read(), isNull);
      expect(AppScope.instance.ride.status, RideStatus.closed);
      final history = await OnDemandRideHistoryStore.read();
      expect(
        history.map((ride) => ride.reservationId),
        contains('ondemand-${snapshot.rideId}'),
      );
    },
  );

  test('markCompleted rejects non-completed statuses', () async {
    await expectLater(
      ActiveRideController().markCompleted(RideStatus.driverAssigned),
      throwsA(isA<ArgumentError>()),
    );
  });
}
