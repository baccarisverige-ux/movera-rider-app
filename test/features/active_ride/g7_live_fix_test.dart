import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/config/rider_app_config.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';

/// G7 live test 2026-11-01.
void main() {
  test('the route change outcome stays long enough to read (>= 4 s)', () {
    expect(
      WaitingForDriver.routeOutcomeNoticeDuration,
      greaterThanOrEqualTo(const Duration(seconds: 4)),
    );
  });

  test('routeChange.beforePickup false is read from the served document', () {
    final config = RiderAppConfig.fromJson({
      ...SeedRiderConfigRepository.seedDocument,
      'routeChange': {'on': true, 'beforePickup': false},
    })!;
    expect(config.routeChangeBeforePickup, isFalse);
    expect(config.routeChangeOn, isTrue);
  });
}
