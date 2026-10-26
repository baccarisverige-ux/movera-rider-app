import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/feature_flags/feature_flags.dart';
import 'package:movera_rider/features/booking/application/booking_coordinator.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/ride_selection/domain/booking_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RideSnapshotStore.epoch = 0;
    FindingDriverController.active = null;
    AppScope.instance.ride
      ..rideId = null
      ..status = RideStatus.idle;
  });

  test(
    'category and payment survive sub-flow changes and reach Book Now snapshot',
    () async {
      final selection = RideSelectionController(flags: const FeatureFlags());
      final xl = selection.rideById('xl');
      selection.selectRide(xl.id, xl.price);
      selection.selectPaymentNamed('Card');
      final selectedPayment = selection
          .payments()[selection.selectedPayment]
          .name;

      // Simulate entering/leaving the booking-time sub-flow without rebuilding
      // a second source of selection truth.
      selection.setBookingMode(BookingMode.scheduled);
      selection.scheduleFor(DateTime(2026, 9, 17, 10));
      selection.setBookingMode(BookingMode.now);

      expect(selection.selectedRideId, 'xl');
      expect(selectedPayment, 'Card');

      final booking = BookingCoordinator(
        api: ApiClient(client: InProcessMockClient()),
      );
      final rideId = await booking.submitFinding(
        pickupAddress: 'Pickup',
        destinationAddress: 'Destination',
        pickupLat: 59.3293,
        pickupLng: 18.0686,
        destinationLat: 59.3326,
        destinationLng: 18.0649,
        rideType: selection.selectedRideId,
        price: selection.priceFor(xl.id, xl.price),
        paymentMethod: selectedPayment,
      );

      final snapshot = await RideSnapshotStore.readForArchive();
      expect(snapshot, isNotNull);
      expect(snapshot!.rideId, rideId);
      expect(snapshot.rideType, 'xl');
      expect(snapshot.paymentMethod, 'Card');
    },
  );
}
