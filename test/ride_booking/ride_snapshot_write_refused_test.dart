import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// uat-r1: the reload snapshot is best effort. On iOS Safari a localStorage
/// write can be refused (quota, Private Browsing on older iOS, "Block All
/// Cookies"); the write is awaited right after the server created the
/// ride ("Confirm and search"), so a refusal there failed the booking the
/// rider had just been charged for, and Finding's later unawaited saves
/// threw into the zone. A refused write is logged and the ride goes on.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/shared_preferences'),
          (call) async {
            if (call.method == 'getAll') return <String, Object>{};
            throw PlatformException(code: 'QuotaExceededError');
          },
        );
    RideSnapshotStore.epoch = 0;
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/shared_preferences'),
          null,
        );
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('a refused snapshot write does not throw into the booking', () async {
    const id = 'ride_uat_r1_refused';
    AppScope.instance.ride
      ..rideId = null
      ..suppressRestore = false
      ..restoreFromBackend(RideStatus.findingDriver, id: id);
    await expectLater(
      RideSnapshotStore.save(
        RideSnapshot(
          status: RideStatus.findingDriver,
          savedAt: DateTime.now(),
          pickupAddress: 'Klockarvägen, Bårsta',
          destinationAddress: 'Södertälje centrum',
          pickupLat: 59.1955,
          pickupLng: 17.6165,
          destinationLat: 59.2000,
          destinationLng: 17.6300,
          rideType: 'Movera',
          price: 259,
          paymentMethod: 'Cash',
          rideId: id,
        ),
      ),
      completes,
    );
  });
}
