// rider-r3-3: the "longer than expected" budget was fixed from the first
// in-trip sample's ETA. A stale pickup ETA (about 20 s) fired a false
// off-route Ride check on a normal trip, and an ETA of 0 turned the
// trigger off for the whole trip.
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/safety/domain/ride_check_monitor.dart';
import 'package:movera_rider/features/safety/domain/ride_check_trigger.dart';

const _pickup = GeoPoint(59.3293, 18.0686);
const _destination = GeoPoint(59.3600, 18.0000);
const _plan = RideCheckPlan(pickup: _pickup, destination: _destination);

final _t0 = DateTime.utc(2026, 10, 15, 14, 0);

/// A point a [fraction] of the way from the pickup to the drop-off.
GeoPoint _along(double fraction) => GeoPoint(
  _pickup.latitude + (_destination.latitude - _pickup.latitude) * fraction,
  _pickup.longitude + (_destination.longitude - _pickup.longitude) * fraction,
);

RideCheckMonitor _monitor() =>
    RideCheckMonitor(settings: const RideCheckTriggerSettings(), plan: _plan);

void main() {
  test('a stale pickup ETA on the first sample does not fire on a normal '
      'trip', () {
    final monitor = _monitor();
    const trip = 600;
    RideCheckDetection? hit;
    for (var s = 0; s <= trip; s += 5) {
      hit ??= monitor.addSample(
        RideCheckSample(
          point: _along(s / trip),
          at: _t0.add(Duration(seconds: s)),
          // The first sample still carries the ETA to pickup.
          etaSeconds: s == 0 ? 20 : trip - s,
        ),
      );
    }
    expect(hit, isNull);
  });

  test('an ETA of 0 on the first sample does not turn the trigger off', () {
    final monitor = _monitor();
    RideCheckDetection? hit;
    // Two hours in slow traffic for a trip of about ten minutes.
    for (var s = 0; s <= 2 * 3600 && hit == null; s += 30) {
      hit = monitor.addSample(
        RideCheckSample(
          point: _along(s / (2 * 3600)),
          at: _t0.add(Duration(seconds: s)),
          etaSeconds: s == 0 ? 0 : null,
          inTraffic: true,
        ),
      );
    }
    expect(hit?.trigger, RideCheckTrigger.offRoute);
    expect(hit!.reason.longerPercent, greaterThanOrEqualTo(50));
  });
}
