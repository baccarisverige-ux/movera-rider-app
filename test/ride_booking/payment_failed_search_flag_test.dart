import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/web/web_search_interrupted.dart';
import 'package:movera_rider/features/active_ride/application/active_ride_controller.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// rider-r5-18: a trip that ended (here: completed, payment failed) and
/// dropped its snapshot also drops the web "search was live" flag, so a
/// reload does not call it an interrupted search.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => debugClearSearchLive = null);

  test('payment failed clears the live-search flag', () async {
    SharedPreferences.setMockInitialValues({});
    RideSnapshotStore.epoch = 0;
    var cleared = 0;
    debugClearSearchLive = () => cleared++;
    const id = 'ride_r5_18';
    AppScope.instance.ride
      ..rideId = null
      ..suppressRestore = false
      ..restoreFromBackend(RideStatus.paymentProcessing, id: id);
    await RideSnapshotStore.save(RideSnapshot(
      status: RideStatus.paymentProcessing,
      savedAt: DateTime.now(),
      pickupAddress: 'A',
      destinationAddress: 'B',
      pickupLat: 59.34,
      pickupLng: 18.05,
      destinationLat: 59.31,
      destinationLng: 18.04,
      rideType: 'Movera',
      price: 259,
      paymentMethod: 'Apple Pay',
      rideId: id,
    ));
    cleared = 0;

    await ActiveRideController().markCompletedPaymentFailed(id);

    expect(cleared, greaterThan(0));
  });
}
