import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/contracts/ride_status.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';

/// G5 live test 2026-10-31: the map kept the "1 min" bubble over the
/// pickup while the driver was already there.
void main() {
  test('no ETA bubble over the pickup once the driver has arrived', () {
    expect(pickupEtaPinShown(RideStatus.driverWaiting), isFalse);
    expect(pickupEtaPinShown(RideStatus.driverArriving), isTrue);
    expect(pickupEtaPinShown(RideStatus.driverAssigned), isTrue);
  });
}
