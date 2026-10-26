import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/active_ride/application/active_ride_controller.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/data/finding_driver_repository.dart';
import 'package:movera_rider/features/finding_driver/presentation/finding_drivers.dart';
import 'package:movera_rider/features/home/presentation/home.dart';
import 'package:movera_rider/features/ride_booking/application/ride_restore_coordinator.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

RideSnapshot findingSnap({String rideId = 'r-late'}) => RideSnapshot(
  status: RideStatus.findingDriver,
  savedAt: DateTime.now(),
  pickupAddress: 'A',
  destinationAddress: 'B',
  pickupLat: 59.3,
  pickupLng: 18.0,
  destinationLat: 59.4,
  destinationLng: 18.1,
  rideType: 'Movera',
  price: 259,
  paymentMethod: 'Apple Pay',
  rideId: rideId,
);

MockRideRealtime get _rt => AppScope.instance.rideRealtime as MockRideRealtime;

void _resetScope() {
  SharedPreferences.setMockInitialValues({});
  RideSnapshotStore.epoch = 0;
  FindingDriverController.active = null;
  final ride = AppScope.instance.ride;
  ride.rideId = null;
  ride.suppressRestore = false;
  ride.restoreFromBackend(RideStatus.idle);
  final rt = _rt;
  rt.cancelled = false;
  rt.disposed = false;
  rt.held = false;
  rt.lastDriver = null;
  rt.lastStatus = RideStatus.idle;
  RideRestoreCoordinator.instance.showing = RestoredSurface.home;
  RideRestoreCoordinator.instance.onReplaceRoot = null;
}

/// Waits for [done] instead of a fixed delay, so a loaded machine does not
/// check before the mock got there (10 ms poll, 5 s deadline). The "never
/// happens" checks keep a fixed wait: slowness can only weaken them.
Future<void> _until(FutureOr<bool> Function() done) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!await done() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// rider-u29: each ride is booked on the app's stand-in server first (quote,
/// then ride), so the mock's accept is the real one. The mock no longer
/// shows a driver the server refused, as it did for the made-up ids these
/// tests used before.
Future<String> _bookOnServer() async {
  final ApiClient api = AppScope.instance.api;
  final quoted = await api.post(
    '/api/v1/quotes',
    body: <String, dynamic>{
      'rideType': 'economy',
      'pickup': <String, dynamic>{'lat': 59.3, 'lng': 18.0},
      'destination': <String, dynamic>{'lat': 59.4, 'lng': 18.1},
    },
  );
  final quote = Map<String, dynamic>.from(quoted['quote'] as Map);
  final created = await api.post(
    '/api/v1/rides',
    body: <String, dynamic>{
      'categoryId': 'economy',
      'paymentMethod': 'apple_pay',
      'pickupAddress': 'A',
      'destinationAddress': 'B',
      'pickupLat': 59.3,
      'pickupLng': 18.0,
      'destinationLat': 59.4,
      'destinationLng': 18.1,
      'quoteId': quote['id'],
      'quoteSignedPayload': quote['signedPayload'],
      'quoteExpiresAt': quote['expiresAt'],
      'quoteTotalMinor': quote['totalMinor'],
      'fare': <String, dynamic>{
        'amountMinor': quote['totalMinor'],
        'currency': quote['currency'],
      },
    },
  );
  return (created['ride'] as Map)['id'] as String;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(_resetScope);
  tearDown(_resetScope);

  test(
    'finding: cancel then late assign stays Home (not Finding/Waiting)',
    () async {
      final rt = _rt;
      final findId = await _bookOnServer();
      final ride = AppScope.instance.ride..rideId = findId;
      var matches = 0;
      final controller = FindingDriverController(
        realtime: rt,
        ride: ride,
        store: FindingDriverRepository(),
      );
      controller.start(
        snapshot: findingSnap(rideId: findId),
        onTick: (_) {},
        onMatched: () => matches += 1,
      );
      // subscribe() clears held — hold after start so the timer cannot fire.
      rt.holdAssignment();

      expect(ride.status, RideStatus.findingDriver);

      await controller.cancelSearch();

      expect(ride.status, RideStatus.cancelledByRider);
      expect(ride.suppressRestore, isTrue);
      expect(rt.cancelled, isTrue);
      expect(await RideSnapshotStore.read(), isNull);

      rt.assignNow();
      rt.emit(RideStatus.driverAssigned, sequence: 50);
      rt.emit(RideStatus.findingDriver, sequence: 51);
      rt.emit(RideStatus.driverWaiting, sequence: 52);
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(matches, 0);
      expect(controller.matchCount, 0);
      expect(ride.status, RideStatus.cancelledByRider);
      expect(await RideSnapshotStore.read(), isNull);

      final restore = RideRestoreCoordinator(reader: RideSnapshotStore.read);
      expect(
        restore.surfaceFor(await RideSnapshotStore.read()),
        RestoredSurface.home,
      );
      expect(await restore.root(), isA<Home>());

      Widget? replaced;
      restore.showing = RestoredSurface.home;
      restore.debugAtRoot = () => true;
      restore.onReplaceRoot = (page) => replaced = page;
      expect(await restore.resumeIfNeeded(), isNull);
      expect(replaced, isNull);
      expect(restore.showing, isNot(RestoredSurface.finding));
      expect(restore.showing, isNot(RestoredSurface.waiting));

      controller.dispose();
    },
  );

  test(
    'waiting: cancel-first then late assign stays Home (not Waiting/Finding)',
    () async {
      final rt = _rt;
      final waitId = await _bookOnServer();
      final ride = AppScope.instance.ride..rideId = waitId;
      var matches = 0;
      final controller = FindingDriverController(
        realtime: rt,
        ride: ride,
        store: FindingDriverRepository(),
      );
      controller.start(
        snapshot: findingSnap(rideId: waitId),
        onTick: (_) {},
        onMatched: () => matches += 1,
      );
      rt.holdAssignment();

      rt.assignNow();
      // The match lands and its snapshot is saved (both async).
      await _until(
        () async =>
            matches == 1 &&
            ride.status == RideStatus.driverAssigned &&
            (await RideSnapshotStore.read())?.status ==
                RideStatus.driverAssigned,
      );
      expect(matches, 1);
      expect(ride.status, RideStatus.driverAssigned);

      // Leave Finding like pushReplacement → Waiting (active cleared).
      controller.dispose();
      expect(FindingDriverController.active, isNull);

      final waitingSnap = await RideSnapshotStore.read();
      expect(waitingSnap, isNotNull);
      final restore = RideRestoreCoordinator(reader: RideSnapshotStore.read);
      expect(restore.surfaceFor(waitingSnap), RestoredSurface.waiting);
      expect(restore.pageFor(waitingSnap), isA<WaitingForDriver>());
      restore.showing = RestoredSurface.waiting;

      // Waiting's cancel path (Finding has already been left).
      await ActiveRideController().markCancelled();

      expect(ride.status, RideStatus.cancelledByRider);
      expect(ride.suppressRestore, isTrue);
      expect(rt.cancelled, isTrue);
      expect(await RideSnapshotStore.read(), isNull);
      expect(
        restore.surfaceFor(await RideSnapshotStore.read()),
        RestoredSurface.home,
      );

      // Late matched / searching events must not reopen Waiting or Finding.
      rt.assignNow();
      rt.emit(RideStatus.driverAssigned, sequence: 80);
      rt.emit(RideStatus.driverArriving, sequence: 81);
      rt.emit(RideStatus.driverWaiting, sequence: 82);
      rt.emit(RideStatus.findingDriver, sequence: 83);
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(ride.status, RideStatus.cancelledByRider);
      expect(await RideSnapshotStore.read(), isNull);
      expect(await restore.root(), isA<Home>());

      Widget? replaced;
      restore.showing = RestoredSurface.home;
      restore.debugAtRoot = () => true;
      restore.onReplaceRoot = (page) => replaced = page;
      final resumed = await restore.resumeIfNeeded();
      expect(resumed, isNull);
      expect(replaced, isNull);
      expect(restore.showing, RestoredSurface.home);
      expect(replaced, isNot(isA<WaitingForDriver>()));
      expect(replaced, isNot(isA<FindingDrivers>()));
    },
  );

  test(
    'cancel-first bumps epoch so a late assigned snapshot save cannot revive Waiting',
    () async {
      final rt = _rt;
      final epochId = await _bookOnServer();
      final ride = AppScope.instance.ride..rideId = epochId;
      final controller = FindingDriverController(
        realtime: rt,
        ride: ride,
        store: FindingDriverRepository(),
      );
      controller.start(
        snapshot: findingSnap(rideId: epochId),
        onTick: (_) {},
        onMatched: () {},
      );
      rt.holdAssignment();

      // In-flight persist started before cancel-first (captures old epoch).
      final pending = RideSnapshotStore.save(
        findingSnap(rideId: epochId).copyWith(
          status: RideStatus.driverAssigned,
          savedAt: DateTime.now(),
          driver: null,
        ),
      );
      await controller.cancelSearch();
      await pending;

      expect(ride.status, RideStatus.cancelledByRider);
      expect(ride.suppressRestore, isTrue);
      expect(await RideSnapshotStore.read(), isNull);

      rt.assignNow();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(await RideSnapshotStore.read(), isNull);

      final restore = RideRestoreCoordinator(reader: RideSnapshotStore.read);
      expect(
        restore.surfaceFor(await RideSnapshotStore.read()),
        RestoredSurface.home,
      );
      expect(await restore.root(), isA<Home>());

      controller.dispose();
    },
  );
}
