import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/features/booking/application/booking_coordinator.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FindingDriverController.active = null;
    AppScope.instance.ride
      ..rideId = null
      ..restoreFromBackend(RideStatus.idle);
    await RideSnapshotStore.clear();
  });

  test('on-demand booking writes canonical backend IDs but keeps UI labels', () async {
    final mock = InProcessMockClient();
    final api = ApiClient(client: mock);
    final booking = BookingCoordinator(api: api);

    final rideId = await booking.submitFinding(
      pickupAddress: 'A',
      destinationAddress: 'B',
      pickupLat: 59.3,
      pickupLng: 18.0,
      destinationLat: 59.4,
      destinationLng: 18.1,
      rideType: 'xl',
      rideTypeLabel: 'Movera XL',
      price: 399,
      paymentMethod: 'apple',
      paymentMethodLabel: 'Apple Pay',
    );

    final response = await api.get('/api/v1/rides/$rideId');
    final ride = Map<String, dynamic>.from(response['ride'] as Map);

    expect(ride['categoryId'], 'xl');
    expect(ride['paymentMethodId'], 'apple');
    expect(ride['rideType'], 'xl');
    // openapi PaymentMethod (rider-r4-5); the id stays paymentMethodId.
    expect(ride['paymentMethod'], 'apple_pay');

    final snapshot = await RideSnapshotStore.read();
    expect(snapshot?.rideType, 'Movera XL');
    expect(snapshot?.paymentMethod, 'Apple Pay');
  });

  test('scheduled booking uses canonical backend field names', () async {
    final mock = InProcessMockClient();
    final api = ApiClient(client: mock);
    final booking = BookingCoordinator(api: api);

    final rideId = await booking.requestBooking(
      rideType: 'premium',
      paymentMethod: 'wallet',
      scheduledAt: '2026-10-01T10:00:00Z',
    );

    final response = await api.get('/api/v1/rides/$rideId');
    final ride = Map<String, dynamic>.from(response['ride'] as Map);

    expect(ride['categoryId'], 'premium');
    expect(ride['paymentMethodId'], 'wallet');
  });
}
