import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/history/data/on_demand_ride_history_store.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RideSnapshotStore.epoch = 0;
  });

  RideSnapshot snapshot() => RideSnapshot(
    status: RideStatus.driverAssigned,
    savedAt: DateTime(2026, 9, 16, 10),
    pickupAddress: 'Pickup',
    destinationAddress: 'Destination',
    pickupLat: 59.3293,
    pickupLng: 18.0686,
    destinationLat: 59.3326,
    destinationLng: 18.0649,
    rideType: 'Movera',
    price: 259,
    paymentMethod: 'Apple Pay',
    rideId: 'ride-archive-failure',
  );

  test(
    'cancel clears active snapshot even when History archival fails',
    () async {
      final active = snapshot();
      await RideSnapshotStore.save(active);
      expect(await RideSnapshotStore.readForArchive(), isNotNull);

      await OnDemandRideHistoryStore.archiveCancelledThenClear(
        snapshot: active,
        reasonId: 'plans_changed',
        archiveWriter: (_, __, ___) async {
          throw StateError('simulated History write failure');
        },
      );

      expect(await RideSnapshotStore.readForArchive(), isNull);
      expect(await OnDemandRideHistoryStore.read(), isEmpty);
    },
  );
}
