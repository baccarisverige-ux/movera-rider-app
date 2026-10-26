import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

RideSnapshot snapshot(
  String rideId, {
  RideStatus status = RideStatus.findingDriver,
}) {
  return RideSnapshot(
    status: status,
    savedAt: DateTime.now(),
    pickupAddress: 'Pickup',
    destinationAddress: 'Destination',
    pickupLat: 59.33,
    pickupLng: 18.06,
    destinationLat: 59.34,
    destinationLng: 18.07,
    rideType: 'Movera',
    price: 100,
    paymentMethod: 'apple_pay',
    rideId: rideId,
  );
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await RideSnapshotStore.clear();
  });

  test('old save then clear then new save preserves the new ride', () async {
    final oldSave = RideSnapshotStore.save(snapshot('ride-old'));
    final clearing = RideSnapshotStore.clear();
    final newSave = RideSnapshotStore.save(snapshot('ride-new'));

    await Future.wait(<Future<void>>[oldSave, clearing, newSave]);

    final restored = await RideSnapshotStore.read();
    expect(restored?.rideId, 'ride-new');
  });

  test('clear invoked after a save wins over that older save', () async {
    final oldSave = RideSnapshotStore.save(snapshot('ride-old'));
    final clearing = RideSnapshotStore.clear();

    await Future.wait(<Future<void>>[oldSave, clearing]);

    expect(await RideSnapshotStore.read(), isNull);
  });

  test('save invoked after clear persists normally', () async {
    final clearing = RideSnapshotStore.clear();
    final freshSave = RideSnapshotStore.save(snapshot('ride-fresh'));

    await Future.wait(<Future<void>>[clearing, freshSave]);

    final restored = await RideSnapshotStore.read();
    expect(restored?.rideId, 'ride-fresh');
  });

  test(
    'concurrent saves resolve in invocation order without deleting the last write',
    () async {
      final first = RideSnapshotStore.save(snapshot('ride-1'));
      final second = RideSnapshotStore.save(snapshot('ride-2'));
      final third = RideSnapshotStore.save(snapshot('ride-3'));

      await Future.wait(<Future<void>>[first, second, third]);

      final restored = await RideSnapshotStore.read();
      expect(restored?.rideId, 'ride-3');
    },
  );

  test('terminal save never overwrites an active ride', () async {
    await RideSnapshotStore.save(snapshot('ride-active'));
    await RideSnapshotStore.save(
      snapshot('ride-cancelled', status: RideStatus.cancelledByRider),
    );

    final restored = await RideSnapshotStore.read();
    expect(restored?.rideId, 'ride-active');
    expect(restored?.status, RideStatus.findingDriver);
  });

  test(
    'lifecycle touch after clear cannot resurrect a cancelled ride',
    () async {
      await RideSnapshotStore.save(snapshot('ride-cancelled'));
      await RideSnapshotStore.clear();

      await RideSnapshotStore.touchCurrent();

      expect(await RideSnapshotStore.read(), isNull);
    },
  );

  test('lifecycle touch keeps the same active ride identity', () async {
    await RideSnapshotStore.save(snapshot('ride-active'));
    final before = await RideSnapshotStore.read();

    await Future<void>.delayed(const Duration(milliseconds: 2));
    await RideSnapshotStore.touchCurrent();

    final after = await RideSnapshotStore.read();
    expect(after?.rideId, 'ride-active');
    expect(after?.status, RideStatus.findingDriver);
    expect(after!.savedAt.isAfter(before!.savedAt), isTrue);
  });

  test(
    'clear then rebook then lifecycle touch preserves only the new ride',
    () async {
      await RideSnapshotStore.save(snapshot('ride-old'));

      final clearing = RideSnapshotStore.clear();
      final rebooking = RideSnapshotStore.save(snapshot('ride-new'));
      final touching = RideSnapshotStore.touchCurrent();

      await Future.wait(<Future<void>>[clearing, rebooking, touching]);

      final restored = await RideSnapshotStore.read();
      expect(restored?.rideId, 'ride-new');
    },
  );

  test(
    'explicit newer save invalidates an older lifecycle touch intent',
    () async {
      await RideSnapshotStore.save(snapshot('ride-old'));

      final touching = RideSnapshotStore.touchCurrent();
      final newerSave = RideSnapshotStore.save(snapshot('ride-new'));

      await Future.wait(<Future<void>>[touching, newerSave]);

      final restored = await RideSnapshotStore.read();
      expect(restored?.rideId, 'ride-new');
    },
  );
}
