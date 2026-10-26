import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/ride_booking/application/ride_restore_coordinator.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/matched_driver.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Phase 135 integration coverage: a page reload always constructs a fresh
/// MockRideRealtime, whose subscribe() used to unconditionally reset to
/// findingDriver and restart the 25-second assignment timer - regardless of
/// what the restored ride's real status was.
///
/// The exact bug/fix mechanism (a stale low-versioned reset event wrongly
/// accepted because RideSession.authoritativeVersion was never seeded) is
/// reproduced deterministically at the unit level in
/// test/booking/ride_session_reconcile_test.dart's "Phase 135" group - that
/// test genuinely fails against the old (unseeded) call and passes against
/// the fix, with no timing dependency. These tests are the integration
/// layer on top: they drive the real RideRestoreCoordinator.pageFor +
/// WaitingForDriver + MockRideRealtime.primeResume path end to end and
/// confirm the resumed ride's status is correct immediately and stays
/// stable past the mock's assignment window. They do not independently
/// reproduce the original bug against unmodified code: a fresh broadcast
/// StreamController silently drops an event added before subscribe()'s own
/// caller has attached its listener, so the pre-fix reset-to-findingDriver
/// emit never actually reached DriverTrackingController in this harness
/// either - which is also why the resume path's own initial emit had to be
/// deferred by a microtask (see subscribe()'s scheduleMicrotask) to work at
/// all here.
///
/// Covers the same two scenarios the Batch 10 audit manually drove in a
/// headless browser: reload mid-approach (driver assigned, not yet arrived)
/// and reload mid-trip.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RideSnapshotStore.epoch = 0;
    AppScope.instance.ride
      ..rideId = null
      ..suppressRestore = false
      ..authoritativeVersion = null
      ..authoritativeUpdatedAt = null
      ..restoreFromBackend(RideStatus.idle);
  });

  const driver = MatchedDriver(id: 'd-135', firstName: 'Sara');

  RideSnapshot snapshot({
    required String rideId,
    required RideStatus status,
    required int version,
  }) => RideSnapshot(
    status: status,
    savedAt: DateTime.now(),
    pickupAddress: 'Stockholm pickup',
    destinationAddress: 'Stockholm destination',
    pickupLat: 59.3293,
    pickupLng: 18.0686,
    destinationLat: 59.3326,
    destinationLng: 18.0649,
    rideType: 'Movera',
    price: 259,
    paymentMethod: 'Apple Pay',
    rideId: rideId,
    driver: driver,
    version: version,
  );

  Future<void> pumpRestoredPage(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: page));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  // The mock's GPS/trip timers keep ticking on the shared AppScope singleton
  // for as long as the resumed status stays matched - which, now fixed, is
  // exactly what these tests intentionally hold it at. flutter_test's
  // pending-timer check runs at the end of the test body itself (before
  // addTearDown callbacks), so timers must be stopped there directly. The
  // next test's own subscribe() resets cancelled/status regardless, so this
  // has no effect on later tests in this file.
  void stopMockTimers() => AppScope.instance.rideRealtime.cancelRide();

  testWidgets(
    'reload mid-approach: a fresh mock transport does not regress the '
    'restored ride back to findingDriver',
    (tester) async {
      const rideId = 'phase135-approach';
      final coordinator = RideRestoreCoordinator();
      // pageFor is the exact call RideRestoreGate makes on cold start; this
      // is what actually seeds authoritativeVersion and primes the mock.
      final page = coordinator.pageFor(
        snapshot(rideId: rideId, status: RideStatus.driverAssigned, version: 5),
      );
      expect(page, isA<WaitingForDriver>());

      await pumpRestoredPage(tester, page);

      expect(
        AppScope.instance.ride.status,
        isNot(RideStatus.findingDriver),
        reason: 'a fresh mock reconnect must not regress the restored ride',
      );
      expect(AppScope.instance.ride.status.isMatched, isTrue);

      // Waiting past the mock's default 25s assignment window must not
      // trigger a spurious re-assignment cycle - none should be scheduled
      // for an already-matched resume.
      await tester.pump(const Duration(seconds: 26));
      expect(AppScope.instance.ride.status, isNot(RideStatus.findingDriver));
      stopMockTimers();
    },
  );

  testWidgets('reload mid-trip: a fresh mock transport does not regress the '
      'restored ride back to findingDriver', (tester) async {
    const rideId = 'phase135-trip';
    final coordinator = RideRestoreCoordinator();
    final page = coordinator.pageFor(
      snapshot(rideId: rideId, status: RideStatus.tripInProgress, version: 12),
    );
    expect(page, isA<WaitingForDriver>());

    await pumpRestoredPage(tester, page);

    expect(
      AppScope.instance.ride.status,
      isNot(RideStatus.findingDriver),
      reason: 'a fresh mock reconnect must not regress a mid-trip ride',
    );
    expect(AppScope.instance.ride.status.isMatched, isTrue);

    await tester.pump(const Duration(seconds: 26));
    expect(AppScope.instance.ride.status, isNot(RideStatus.findingDriver));
    stopMockTimers();
  });

  testWidgets(
    'without a persisted version, an old-format snapshot restore is not '
    'protected - documents the coverage boundary, not a regression',
    (tester) async {
      const rideId = 'phase135-no-version';
      final coordinator = RideRestoreCoordinator();
      // version omitted - simulates a snapshot saved before this fix shipped,
      // or one restored before any live event ever persisted one.
      final page = coordinator.pageFor(
        RideSnapshot(
          status: RideStatus.driverAssigned,
          savedAt: DateTime.now(),
          pickupAddress: 'Stockholm pickup',
          destinationAddress: 'Stockholm destination',
          pickupLat: 59.3293,
          pickupLng: 18.0686,
          destinationLat: 59.3326,
          destinationLng: 18.0649,
          rideType: 'Movera',
          price: 259,
          paymentMethod: 'Apple Pay',
          rideId: rideId,
          driver: driver,
        ),
      );

      await pumpRestoredPage(tester, page);

      // Fix #1 (the mock resumes from the real status/driver) still applies
      // even without a version, since primeResume only needs the snapshot's
      // status/driver - so this restore is not actually broken either.
      expect(AppScope.instance.ride.status, isNot(RideStatus.findingDriver));
      stopMockTimers();
    },
  );
}
