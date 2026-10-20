import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/config/trip_zone_config.dart';
import 'package:movera_rider/features/ride_booking/data/driver_repository.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/matched_driver.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_complete/data/last_completed_ride.dart';

/// The completion screen used to apologise three times over — driver, receipt
/// and tips all unavailable — while the finished ride sat right there.
void main() {
  setUp(LastCompletedRide.clear);
  tearDown(LastCompletedRide.clear);

  RideSnapshot finished() => RideSnapshot(
    status: RideStatus.tripCompleted,
    rideId: 'ride_done_1',
    pickupAddress: 'Sveavägen 1',
    destinationAddress: 'Hornsgatan 2',
    pickupLat: 59.34,
    pickupLng: 18.05,
    destinationLat: 59.31,
    destinationLng: 18.04,
    rideType: 'Movera',
    price: 259,
    paymentMethod: 'Apple Pay',
    savedAt: DateTime(2026, 9, 18, 7, 5),
    driver: const MatchedDriver(
      id: 'drv_1',
      firstName: 'Elin',
      rating: 4.9,
      tripCount: 2140,
      vehicleMake: 'Volvo',
      vehicleModel: 'XC40',
      vehicleColor: 'Black',
      plate: 'MVR 204',
    ),
  );

  test('receipt comes from the completed ride, in SEK', () {
    LastCompletedRide.remember(finished());
    final receipt = const TripReceiptRepository().last();

    expect(receipt, isNotNull);
    expect(receipt!.pickup, 'Sveavägen 1');
    expect(receipt.destination, 'Hornsgatan 2');
    expect(receipt.total, '259 kr');
    expect(receipt.total, isNot(contains(r'$')));
    expect(receipt.method, 'Apple Pay');
    expect(receipt.isFinal, isFalse);
  });

  test('driver profile comes from the completed ride', () {
    LastCompletedRide.remember(finished());
    final driver = const DriverRepository().current();

    expect(driver, isNotNull);
    expect(driver!.name, 'Elin');
    expect(driver.plate, 'MVR 204');
    expect(driver.vehicle, 'Black Volvo XC40');
    expect(driver.ratingLabel, '4.9');
  });

  test('no completed ride keeps the honest empty state', () {
    expect(const TripReceiptRepository().last(), isNull);
    expect(const DriverRepository().current(), isNull);
  });

  test('a completed ride without a driver still yields a receipt', () {
    LastCompletedRide.remember(
      RideSnapshot(
        status: RideStatus.tripCompleted,
        rideId: 'ride_done_2',
        pickupAddress: 'A',
        destinationAddress: 'B',
        pickupLat: 59.34,
        pickupLng: 18.05,
        destinationLat: 59.31,
        destinationLng: 18.04,
        rideType: 'Movera',
        price: 120,
        paymentMethod: 'Cash',
        savedAt: DateTime(2026, 9, 18, 7, 5),
      ),
    );
    expect(const TripReceiptRepository().last()?.total, '120 kr');
    expect(const DriverRepository().current(), isNull);
  });

  test('an explicitly passed profile still wins', () {
    LastCompletedRide.remember(finished());
    const injected = DriverProfile(
      name: 'Injected',
      tagline: 't',
      vehicle: 'v',
      plate: 'p',
      rideNumber: 'r',
      ratingLabel: '5.0',
      completedAt: 'now',
    );
    expect(const DriverRepository(current: injected).current()?.name, 'Injected');
  });

  test('tip amounts are offered in SEK without a trip in another currency', () {
    final amounts = seedConfigForTrip('SEK')!.enabledTips;
    expect(amounts, isNotEmpty);
    for (final amount in amounts) {
      expect(amount.currency, 'SEK');
    }
  });
}
