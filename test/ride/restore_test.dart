import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/finding_driver/presentation/finding_drivers.dart';
import 'package:movera_rider/features/home/presentation/home.dart';
import 'package:movera_rider/features/ride_booking/application/ride_restore_coordinator.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_complete/presentation/ride_completed.dart';
import 'package:shared_preferences/shared_preferences.dart';

RideSnapshot snap(RideStatus status, {DateTime? savedAt}) {
  return RideSnapshot(
    status: status,
    savedAt: savedAt ?? DateTime.now(),
    pickupAddress: 'A',
    destinationAddress: 'B',
    pickupLat: 59.3,
    pickupLng: 18.0,
    destinationLat: 59.4,
    destinationLng: 18.1,
    rideType: 'Movera',
    price: 259,
    paymentMethod: 'Apple Pay',
    rideId: 'r1',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  test('cold start finding driver', () {
    final c = RideRestoreCoordinator(
      reader: () async => snap(RideStatus.findingDriver),
    );
    final page = c.pageFor(snap(RideStatus.findingDriver));
    expect(page, isA<FindingDrivers>());
    expect(c.showing, RestoredSurface.finding);
  });

  test('cold start delayed search stays on finding', () {
    final c = RideRestoreCoordinator(
      reader: () async => snap(RideStatus.searchDelayed),
    );
    expect(c.pageFor(snap(RideStatus.searchDelayed)), isA<FindingDrivers>());
    expect(c.showing, RestoredSurface.finding);
  });

  test('cold start assigned', () {
    final c = RideRestoreCoordinator(reader: () async => null);
    expect(c.pageFor(snap(RideStatus.driverAssigned)), isA<WaitingForDriver>());
  });

  test('cold start arriving and waiting restore to matched', () {
    final c = RideRestoreCoordinator(reader: () async => null);
    expect(c.pageFor(snap(RideStatus.driverArriving)), isA<WaitingForDriver>());
    expect(c.showing, RestoredSurface.waiting);
    expect(c.pageFor(snap(RideStatus.driverWaiting)), isA<WaitingForDriver>());
    expect(c.showing, RestoredSurface.waiting);
  });

  test('trip active and approaching dropoff use waiting surface', () {
    final c = RideRestoreCoordinator(reader: () async => null);
    expect(c.pageFor(snap(RideStatus.tripInProgress)), isA<WaitingForDriver>());
    expect(
      c.pageFor(snap(RideStatus.approachingDropoff)),
      isA<WaitingForDriver>(),
    );
    expect(c.showing, RestoredSurface.waiting);
  });

  test('completed restores the exact post-trip status and ride id', () {
    final c = RideRestoreCoordinator(reader: () async => null);
    final completed = c.pageFor(snap(RideStatus.ratingPending));
    expect(completed, isA<RideCompleted>());
    final page = completed as RideCompleted;
    expect(page.status, RideStatus.ratingPending);
    expect(page.rideId, 'r1');
    expect(c.showing, RestoredSurface.complete);
  });

  test('cancelled and stale go home', () {
    final c = RideRestoreCoordinator(reader: () async => null);
    expect(c.pageFor(snap(RideStatus.cancelledByRider)), isA<Home>());
    expect(
      c.pageFor(
        snap(
          RideStatus.findingDriver,
          savedAt: DateTime.now().subtract(const Duration(hours: 3)),
        ),
      ),
      isA<Home>(),
    );
  });

  test('goHome replaces a restored finding surface', () {
    final c = RideRestoreCoordinator(reader: () async => null);
    Widget? shown;
    c.onReplaceRoot = (page) => shown = page;
    c.pageFor(snap(RideStatus.findingDriver));
    expect(c.showing, RestoredSurface.finding);
    c.goHome();
    expect(c.showing, RestoredSurface.home);
    expect(shown, isA<Home>());
  });

  test('goHome can reveal existing Home without rebuilding the root child', () {
    final c = RideRestoreCoordinator(reader: () async => null);
    Widget? shown;
    c.onReplaceRoot = (page) => shown = page;
    c.showing = RestoredSurface.home;

    c.goHome(replaceRoot: false);

    expect(c.showing, RestoredSurface.home);
    expect(shown, isNull);
  });

  test(
    'replaceRootSurface updates a restored stage without replacing Navigator root',
    () {
      final c = RideRestoreCoordinator(reader: () async => null);
      Widget? shown;
      c.onReplaceRoot = (page) => shown = page;

      final replaced = c.replaceRootSurface(
        const Home(),
        RestoredSurface.finding,
      );

      expect(replaced, isTrue);
      expect(c.showing, RestoredSurface.finding);
      expect(shown, isA<Home>());
    },
  );

  test(
    'replaceRootSurface reports unavailable when restore gate is absent',
    () {
      final c = RideRestoreCoordinator(reader: () async => null);
      c.showing = RestoredSurface.waiting;

      final replaced = c.replaceRootSurface(
        const Home(),
        RestoredSurface.finding,
      );

      expect(replaced, isFalse);
      expect(c.showing, RestoredSurface.waiting);
    },
  );

  test('resume is idempotent when already showing', () async {
    final snapshot = snap(RideStatus.findingDriver);
    final c = RideRestoreCoordinator(reader: () async => snapshot);
    c.showing = RestoredSurface.finding;
    expect(await c.resumeIfNeeded(), isNull);
  });

  test('repeated resume does not loop', () async {
    final snapshot = snap(RideStatus.findingDriver);
    final c = RideRestoreCoordinator(reader: () async => snapshot);
    c.showing = RestoredSurface.finding;
    expect(await c.resumeIfNeeded(), isNull);
    expect(await c.resumeIfNeeded(), isNull);
  });

  test('resume does not yank an intentional non-root screen', () async {
    final snapshot = snap(RideStatus.findingDriver);
    final c = RideRestoreCoordinator(reader: () async => snapshot);
    c.showing = RestoredSurface.home;
    c.debugAtRoot = () => false;
    expect(await c.resumeIfNeeded(), isNull);
    expect(c.showing, RestoredSurface.home);
  });

  test('cold start finding never builds Home', () async {
    final c = RideRestoreCoordinator(
      reader: () async => snap(RideStatus.findingDriver),
    );
    final page = await c.root();
    expect(page, isA<FindingDrivers>());
    expect(c.showing, RestoredSurface.finding);
  });

  test('cold start assigned never builds Home', () async {
    final c = RideRestoreCoordinator(
      reader: () async => snap(RideStatus.driverAssigned),
    );
    final page = await c.root();
    expect(page, isA<WaitingForDriver>());
    expect(c.showing, RestoredSurface.waiting);
  });

  test('resume with older surface stays on waiting', () async {
    final snapshot = snap(RideStatus.driverAssigned);
    final c = RideRestoreCoordinator(reader: () async => snapshot);
    c.showing = RestoredSurface.waiting;
    c.debugAtRoot = () => true;
    expect(await c.resumeIfNeeded(), isNull);
  });

  test('public web cold start restores an assigned snapshot', () async {
    final c = RideRestoreCoordinator(
      reader: () async => snap(RideStatus.driverAssigned),
    );
    final page = await c.root();
    expect(page, isA<WaitingForDriver>());
    expect(c.showing, RestoredSurface.waiting);
  });

  test('forced skipRestore still ignores finding on resume', () async {
    Widget? replaced;
    final c = RideRestoreCoordinator(
      reader: () async => snap(RideStatus.findingDriver),
      skipRestore: () => true,
    );
    c.showing = RestoredSurface.home;
    c.debugAtRoot = () => true;
    c.onReplaceRoot = (page) => replaced = page;
    expect(await c.resumeIfNeeded(), isNull);
    expect(replaced, isNull);
    expect(c.showing, RestoredSurface.home);
  });

  test('pagehide keeps the snapshot so a crash can restore the trip', () async {
    await RideSnapshotStore.save(snap(RideStatus.driverAssigned));
    expect(await RideSnapshotStore.read(), isNotNull);

    Widget? shown;
    final c = RideRestoreCoordinator(reader: RideSnapshotStore.read);
    c.onReplaceRoot = (page) => shown = page;
    c.showing = RestoredSurface.waiting;

    c.onPageHide();
    await Future<void>.delayed(Duration.zero);

    expect(await RideSnapshotStore.read(), isNotNull);
    expect(c.showing, RestoredSurface.waiting);
    expect(shown, isNull);
  });

  test('pagehide during finding also keeps the search', () async {
    await RideSnapshotStore.save(snap(RideStatus.findingDriver));
    expect(await RideSnapshotStore.read(), isNotNull);

    Widget? shown;
    final c = RideRestoreCoordinator(reader: RideSnapshotStore.read);
    c.onReplaceRoot = (page) => shown = page;
    c.showing = RestoredSurface.finding;

    c.onPageHide();
    await Future<void>.delayed(Duration.zero);

    expect(await RideSnapshotStore.read(), isNotNull);
    expect(c.showing, RestoredSurface.finding);
    expect(shown, isNull);
  });

  test('skipRestore resume forces Home when showing waiting', () async {
    Widget? shown;
    final c = RideRestoreCoordinator(
      reader: () async => snap(RideStatus.driverAssigned),
      skipRestore: () => true,
    );
    c.showing = RestoredSurface.waiting;
    c.onReplaceRoot = (page) => shown = page;
    expect(await c.resumeIfNeeded(), isNull);
    expect(c.showing, RestoredSurface.home);
    expect(shown, isA<Home>());
  });
}
