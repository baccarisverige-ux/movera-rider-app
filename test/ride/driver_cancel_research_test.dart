import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/realtime/mock_driver_pool.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/history/data/on_demand_ride_history_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A driver dropping the ride before pickup is not the rider's ride ending.
/// Dispatch looks again, so the rider keeps their ride, their price and their
/// addresses — and must not be filed in History as a cancelled trip.
/// Waits until [done] holds (at most 5 s), instead of a fixed delay that a
/// loaded machine can outrun.
Future<void> _until(bool Function() done) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!done() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('driver cancel returns the ride to searching', () async {
    final rt = MockRideRealtime(assignAfter: const Duration(milliseconds: 10));
    addTearDown(rt.dispose);

    final seen = <RideStatus>[];
    rt.subscribe('ride_dc_1').listen((e) => seen.add(e.status));
    rt.assignNow();
    await _until(() => rt.lastStatus == RideStatus.driverAssigned);
    expect(rt.lastStatus, RideStatus.driverAssigned);

    rt.cancelByDriver();
    await _until(() => seen.contains(RideStatus.cancelledByDriver));
    expect(seen, contains(RideStatus.cancelledByDriver));

    rt.researchAfterDriverCancel();
    await _until(() => rt.lastStatus == RideStatus.driverAssigned);

    expect(rt.lastStatus, RideStatus.driverAssigned);
    expect(rt.lastDriver, isNotNull);
  });

  test('the replacement is a different driver', () async {
    final rt = MockRideRealtime(assignAfter: const Duration(milliseconds: 10));
    addTearDown(rt.dispose);

    rt.subscribe('ride_dc_2');
    rt.assignNow();
    await _until(() => rt.lastStatus == RideStatus.driverAssigned);
    final first = rt.lastDriver;

    rt.cancelByDriver();
    rt.researchAfterDriverCancel();
    await _until(() =>
        rt.lastStatus == RideStatus.driverAssigned &&
        rt.lastDriver?.id != first?.id);

    expect(first, isNotNull);
    expect(rt.lastDriver, isNotNull);
    expect(rt.lastDriver!.id, isNot(first!.id));
  });

  test('a dropped ride is not filed as a cancelled trip', () async {
    final rt = MockRideRealtime(assignAfter: const Duration(milliseconds: 10));
    addTearDown(rt.dispose);

    rt.subscribe('ride_dc_3');
    rt.assignNow();
    await _until(() => rt.lastStatus == RideStatus.driverAssigned);
    rt.cancelByDriver();
    rt.researchAfterDriverCancel();
    await _until(() => rt.lastStatus == RideStatus.driverAssigned);

    expect(await OnDemandRideHistoryStore.read(), isEmpty);
  });

  test('a completed ride ignores a late driver cancel', () async {
    final rt = MockRideRealtime(assignAfter: const Duration(milliseconds: 10));
    addTearDown(rt.dispose);

    rt.subscribe('ride_dc_4');
    rt.assignNow();
    await _until(() => rt.lastStatus == RideStatus.driverAssigned);
    rt.lastStatus = RideStatus.tripCompleted;

    rt.cancelByDriver();
    expect(rt.lastStatus, RideStatus.tripCompleted);
  });

  test('the pool offers someone new on each attempt', () {
    final first = MockDriverPool.forRide('ride_x');
    final second = MockDriverPool.forRide('ride_x', attempt: 1);
    final third = MockDriverPool.forRide('ride_x', attempt: 2);
    expect({first.id, second.id, third.id}.length, 3);
  });
}
