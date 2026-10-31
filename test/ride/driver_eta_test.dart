import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/finding_driver/domain/driver_eta.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/matched_driver.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';

void main() {
  test('headline uses distance and eta, not a fake countdown', () {
    final now = DateTime(2026, 9, 13, 3, 0);
    final far = DriverEta.fromFix(
      latitude: 59.34,
      longitude: 18.08,
      pickupLat: 59.3293,
      pickupLng: 18.0686,
      locationAt: now,
      now: now,
    );
    expect(far.headline(), startsWith('Pickup in'));
    expect(far.stale, isFalse);

    final close = DriverEta.fromFix(
      latitude: 59.3294,
      longitude: 18.0687,
      pickupLat: 59.3293,
      pickupLng: 18.0686,
      locationAt: now,
      now: now,
    );
    expect(close.headline(), 'Driver is almost there');
  });

  test('stale GPS shows updating, not invented movement', () {
    final now = DateTime(2026, 9, 13, 3, 0);
    final eta = DriverEta.fromFix(
      latitude: 59.33,
      longitude: 18.07,
      pickupLat: 59.3293,
      pickupLng: 18.0686,
      // v0.18.7 (`pickupWaiting.eta.staleAfterSeconds`): stale after 120 s,
      // so a parked driver's rarer fixes are not "updating location".
      locationAt: now.subtract(const Duration(seconds: 130)),
      now: now,
    );
    expect(eta.stale, isTrue);
    expect(eta.headline(), 'Updating driver location…');
  });

  test('arrived uses driverWaiting status', () {
    const eta = DriverEta(seconds: 20, stale: false);
    expect(
      eta.headline(status: RideStatus.driverWaiting),
      'Driver has arrived',
    );
  });

  test('on-trip copy stays on the waiting surface', () {
    const eta = DriverEta(seconds: 20, stale: false);
    expect(eta.headline(status: RideStatus.tripStarted), 'Ride in progress');
    expect(eta.headline(status: RideStatus.tripInProgress), 'Ride in progress');
    expect(
      eta.subtitle(firstName: 'Alex', status: RideStatus.tripInProgress),
      'Alex is taking you to drop-off.',
    );
  });

  test('close GPS does not declare arrived without driverWaiting', () {
    const eta = DriverEta(seconds: 30, distanceMeters: 40, stale: false);
    expect(
      eta.headline(status: RideStatus.driverAssigned),
      'Driver is almost there',
    );
    expect(
      eta.headline(status: RideStatus.driverArriving),
      'Driver is almost there',
    );
    expect(
      eta.headline(status: RideStatus.driverWaiting),
      'Driver has arrived',
    );
  });

  test('matched driver omits fields that are not supplied', () {
    const driver = MatchedDriver(id: 'd1', firstName: 'Alex', plate: 'MVR 421');
    expect(driver.ratingLabel, isNull);
    expect(driver.tripsLabel, isNull);
    expect(driver.languages, isEmpty);
    expect(MatchedDriver.fromJson(driver.toJson())?.plate, 'MVR 421');
  });
}
