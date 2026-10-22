import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/realtime/mock_driver_pool.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';

/// A matched ride has to know its driver. Without one the arrival sheet has no
/// name, the ride screen and receipt both read "Driver details unavailable",
/// and History archives a driverless trip.
void main() {
  test('assignment attaches a driver to the ride', () async {
    final rt = MockRideRealtime(assignAfter: const Duration(milliseconds: 10));
    addTearDown(rt.dispose);

    rt.subscribe('ride_driver_1');
    rt.assignNow();
    await Future<void>.delayed(const Duration(milliseconds: 80));

    final driver = rt.lastDriver;
    expect(driver, isNotNull);
    expect(driver!.firstName, isNotEmpty);
    expect(driver.plate, isNotNull);
    expect(driver.plate, isNotEmpty);
  });

  test('one ride keeps one driver', () {
    final first = MockDriverPool.forRide('ride_abc');
    final again = MockDriverPool.forRide('ride_abc');
    expect(first.id, again.id);
  });

  test('different rides can draw different drivers', () {
    final ids = <String>{
      for (var i = 0; i < 40; i++) MockDriverPool.forRide('ride_$i').id,
    };
    expect(ids.length, greaterThan(1));
  });

  // The guard that replaces "the mock never invents a driver" (no screen,
  // controller or feature repository conjures a driver of its own; mock
  // identities live behind the API boundary) is a source rule, so it lives
  // in test/architecture/guard_test.dart ('layer imports respect
  // boundaries'), rider-101.

  test('pool carries no removed demo identity', () {
    for (var i = 0; i < 10; i++) {
      final d = MockDriverPool.forRide('ride_$i');
      expect(d.firstName, isNot('Linnea'));
      expect(d.firstName, isNot('Merle'));
      expect(d.plate, isNot('MVR 418'));
    }
  });
}
