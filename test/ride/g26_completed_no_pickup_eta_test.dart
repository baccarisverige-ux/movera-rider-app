import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/finding_driver/domain/driver_eta.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';

/// G26 / G-S7 (screen-switch report 2026-11-12): when the driver finished,
/// the trip sheet flashed the to-pickup line ("Arrives in 1 min · 90 m",
/// "Meet Test now") on the parked map before the summary. The status is
/// tripCompleted while waiting_for_driver_stages.dart _openCompleted parks
/// the map; waiting_for_driver_sheet.dart _headlineFor then falls through to
/// DriverEta.headline, which treated every non-trip status as "coming".
void main() {
  const eta = DriverEta(seconds: 40, distanceMeters: 90, stale: false);
  for (final status in [
    RideStatus.tripCompleted,
    RideStatus.paymentProcessing,
    RideStatus.paymentFinalized,
    RideStatus.ratingPending,
  ]) {
    test('$status shows no pickup ETA', () {
      expect(eta.headline(status: status), 'Trip completed');
      expect(
        eta.subtitle(firstName: 'Test', status: status),
        isNot(contains('Test')),
      );
      expect(eta.subtitle(status: status), isNot(contains('now')));
    });
  }
}
