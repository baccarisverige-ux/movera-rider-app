import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';

void main() {
  test(
    'no-driver terminal event prevents a later automatic assignment',
    () async {
      final rt = MockRideRealtime(
        assignAfter: const Duration(milliseconds: 30),
      );
      addTearDown(rt.dispose);
      final seen = <RideStatus>[];
      rt
          .subscribe('inverse-no-driver')
          .listen((event) => seen.add(event.status));

      rt.emit(RideStatus.noDriverFound);
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(rt.lastStatus, RideStatus.noDriverFound);
      expect(seen, isNot(contains(RideStatus.driverAssigned)));
    },
  );

  test(
    'driver cancellation at pickup stops boarding and trip completion',
    () async {
      final rt = MockRideRealtime(
        assignAfter: const Duration(days: 1),
        boardAfter: const Duration(milliseconds: 20),
        tripTick: const Duration(milliseconds: 5),
        tripTicks: 2,
      );
      addTearDown(rt.dispose);
      final seen = <RideStatus>[];
      rt
          .subscribe('inverse-driver-cancel')
          .listen((event) => seen.add(event.status));

      rt.assignNow();
      rt.markArrivedForTest();
      rt.emit(RideStatus.cancelledByDriver);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(rt.lastStatus, RideStatus.cancelledByDriver);
      expect(seen, isNot(contains(RideStatus.tripStarted)));
      expect(seen, isNot(contains(RideStatus.tripCompleted)));
    },
  );

  test(
    'system cancellation during an active trip stops later completion',
    () async {
      final rt = MockRideRealtime(
        assignAfter: const Duration(days: 1),
        boardAfter: Duration.zero,
        tripTick: const Duration(milliseconds: 20),
        tripTicks: 4,
      );
      addTearDown(rt.dispose);
      final seen = <RideStatus>[];
      rt
          .subscribe('inverse-system-cancel')
          .listen((event) => seen.add(event.status));

      rt.assignNow();
      rt.markArrivedForTest();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(seen, contains(RideStatus.tripStarted));

      rt.emit(RideStatus.cancelledBySystem);
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(rt.lastStatus, RideStatus.cancelledBySystem);
      expect(
        seen.where((status) => status == RideStatus.tripCompleted),
        isEmpty,
      );
    },
  );
}
