import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/config/zone_clock.dart';
import 'package:movera_rider/features/scheduled_rides/application/stockholm_schedule.dart';

/// rider-r5-8: the earliest (and default) pickup is a time the zone's
/// clock shows; on spring-forward night 02:20 does not exist, 03:20 does.
void main() {
  test('the default pickup skips the spring-forward gap', () {
    const schedule = PickupSchedule(ZoneClock.stockholm);
    final now = DateTime.utc(2026, 3, 29, 0, 50); // 01:50 CET
    expect(schedule.defaultPickup(now), DateTime.utc(2026, 3, 29, 3, 20));
    expect(schedule.minimumPickup(now), DateTime.utc(2026, 3, 29, 3, 20));
  });
}
