import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/features/active_ride/application/active_ride_controller.dart';
import 'package:movera_rider/features/history/data/on_demand_ride_history_store.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';
import 'package:movera_rider/features/reservations/presentation/reservation_format.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// rider-u34: a trip whose payment failed is a trip the rider took. Waiting
/// handed `paymentFailed` to [ActiveRideController.markExternalTerminal],
/// which archived only the cancel/no-show/failed statuses and then cleared
/// the snapshot, so the ride vanished from History with no receipt.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const rideId = 'ride_payment_failed_1';

  RideSnapshot inTrip() => RideSnapshot(
    status: RideStatus.tripInProgress,
    savedAt: DateTime.now(),
    pickupAddress: 'Sveavägen 1',
    destinationAddress: 'Stockholm Arlanda Airport',
    pickupLat: 59.34,
    pickupLng: 18.05,
    destinationLat: 59.65,
    destinationLng: 17.93,
    rideType: 'Movera',
    price: 659,
    paymentMethod: 'Apple Pay',
    rideId: rideId,
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    RideSnapshotStore.epoch = 0;
    AppScope.instance.ride
      ..rideId = null
      ..suppressRestore = false
      ..authoritativeVersion = null
      ..authoritativeUpdatedAt = null
      ..restoreFromBackend(RideStatus.idle);
    await RideSnapshotStore.save(inTrip());
    AppScope.instance.ride.restoreFromBackend(
      RideStatus.tripInProgress,
      id: rideId,
    );
  });

  test(
    'a trip that ends in paymentFailed is kept in History as completed',
    () async {
      await ActiveRideController().markExternalTerminal(
        RideStatus.paymentFailed,
      );

      expect(AppScope.instance.ride.status, RideStatus.paymentFailed);
      expect(await RideSnapshotStore.read(), isNull);

      final history = await OnDemandRideHistoryStore.read();
      expect(history, hasLength(1));
      final record = history.single;
      expect(record.reservationId, 'ondemand-$rideId');
      expect(record.status, ReservationStatus.completed);
      expect(record.paymentFailed, isTrue);
      expect(ReservationFormat.historyStatus(record), 'Payment failed');
    },
  );

  test('the other external terminals still archive as before', () async {
    await ActiveRideController().markExternalTerminal(
      RideStatus.cancelledBySystem,
    );
    final record = (await OnDemandRideHistoryStore.read()).single;
    expect(record.status, ReservationStatus.cancelled);
    expect(record.paymentFailed, isFalse);
  });
}
