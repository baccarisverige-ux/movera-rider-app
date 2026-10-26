import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';

/// The finished-ride screen existed but nothing could reach it: the mock
/// stopped at the driver waiting on the kerb, so a ride never ended.
///
/// Each step waits on the status it needs, not a fixed delay, so a loaded
/// machine cannot run the next step before the mock reached the last one.
/// Only the "never happens" checks still wait a fixed time: on a slow machine
/// that can only make them weaker, never fail them.
Future<void> _until(bool Function() done) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!done() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  test('a ride runs through boarding to completion', () async {
    final rt = MockRideRealtime(
      assignAfter: const Duration(milliseconds: 10),
      boardAfter: const Duration(milliseconds: 10),
      tripTick: const Duration(milliseconds: 5),
      tripTicks: 3,
    );
    addTearDown(rt.dispose);

    final seen = <RideStatus>[];
    rt.subscribe('ride_finish_1').listen((e) => seen.add(e.status));

    rt.assignNow();
    rt.lastLat = 59.3400;
    rt.lastLng = 18.0550;
    rt.markArrivedForTest();

    await _until(() => seen.contains(RideStatus.tripCompleted));

    expect(seen, contains(RideStatus.tripStarted));
    expect(seen.last, RideStatus.tripCompleted);
    expect(rt.lastStatus.isCompletedSurface, isTrue);
  });

  test(
    'happy path statuses stay in rider-visible order through rating',
    () async {
      final rt = MockRideRealtime(
        assignAfter: const Duration(days: 1),
        boardAfter: Duration.zero,
        tripTick: const Duration(milliseconds: 2),
        tripTicks: 2,
        paymentProcessingAfter: const Duration(milliseconds: 4),
        paymentFinalizedAfter: const Duration(milliseconds: 4),
        ratingPendingAfter: const Duration(milliseconds: 4),
      );
      addTearDown(rt.dispose);

      final seen = <RideStatus>[];
      rt.subscribe('ride_order_1').listen((e) => seen.add(e.status));

      rt.assignNow();
      await _until(() => seen.contains(RideStatus.driverAssigned));
      rt.markArrivedForTest();
      await _until(() => seen.contains(RideStatus.ratingPending));

      for (final pair in <(RideStatus, RideStatus)>[
        (RideStatus.driverAssigned, RideStatus.driverWaiting),
        (RideStatus.driverWaiting, RideStatus.tripStarted),
        (RideStatus.tripStarted, RideStatus.tripInProgress),
        (RideStatus.tripInProgress, RideStatus.tripCompleted),
        (RideStatus.tripCompleted, RideStatus.paymentProcessing),
        (RideStatus.paymentProcessing, RideStatus.paymentFinalized),
        (RideStatus.paymentFinalized, RideStatus.ratingPending),
      ]) {
        final before = seen.indexOf(pair.$1);
        final after = seen.indexOf(pair.$2);
        expect(before, greaterThanOrEqualTo(0), reason: pair.$1.name);
        expect(
          after,
          greaterThan(before),
          reason: '${pair.$1.name} -> ${pair.$2.name}',
        );
      }
    },
  );

  test('demo completion advances through payment to rating pending', () async {
    final rt = MockRideRealtime(
      assignAfter: const Duration(days: 1),
      boardAfter: Duration.zero,
      tripTick: const Duration(milliseconds: 2),
      tripTicks: 1,
      paymentProcessingAfter: const Duration(milliseconds: 5),
      paymentFinalizedAfter: const Duration(milliseconds: 5),
      ratingPendingAfter: const Duration(milliseconds: 5),
    );
    addTearDown(rt.dispose);

    final seen = <RideStatus>[];
    rt.subscribe('ride_rating_1').listen((e) => seen.add(e.status));

    rt.assignNow();
    await _until(() => seen.contains(RideStatus.driverAssigned));
    rt.markArrivedForTest();

    await _until(() => seen.contains(RideStatus.ratingPending));

    expect(seen, contains(RideStatus.tripCompleted));
    expect(seen, contains(RideStatus.paymentProcessing));
    expect(seen, contains(RideStatus.paymentFinalized));
    expect(seen, contains(RideStatus.ratingPending));
    expect(rt.lastStatus, RideStatus.ratingPending);
  });

  test(
    'disposing after completion stops post-trip rating progression',
    () async {
      final rt = MockRideRealtime(
        assignAfter: const Duration(days: 1),
        boardAfter: Duration.zero,
        tripTick: const Duration(milliseconds: 2),
        tripTicks: 1,
        paymentProcessingAfter: const Duration(milliseconds: 20),
        paymentFinalizedAfter: const Duration(milliseconds: 20),
        ratingPendingAfter: const Duration(milliseconds: 20),
      );

      final seen = <RideStatus>[];
      rt.subscribe('ride_rating_2').listen((e) => seen.add(e.status));

      rt.assignNow();
      await _until(() => seen.contains(RideStatus.driverAssigned));
      rt.markArrivedForTest();
      await _until(() => seen.contains(RideStatus.tripCompleted));
      rt.dispose();

      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(seen, contains(RideStatus.tripCompleted));
      expect(seen, isNot(contains(RideStatus.ratingPending)));
    },
  );

  test('cancelling stops the ride advancing to completion', () async {
    final rt = MockRideRealtime(
      assignAfter: const Duration(milliseconds: 10),
      boardAfter: const Duration(milliseconds: 20),
      tripTick: const Duration(milliseconds: 5),
      tripTicks: 3,
    );
    addTearDown(rt.dispose);

    final seen = <RideStatus>[];
    rt.subscribe('ride_finish_2').listen((e) => seen.add(e.status));

    rt.assignNow();
    rt.lastLat = 59.3400;
    rt.lastLng = 18.0550;
    rt.markArrivedForTest();
    rt.cancelRide();

    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(seen, isNot(contains(RideStatus.tripCompleted)));
  });
}
