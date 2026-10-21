import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'audit_fix_cancel_in_flight_harness.dart';

/// rider-u54: the cancel sheet fixed its phase ("Cancel ride?", free) when
/// it opened. If the trip started while the sheet or the reason sheet was
/// open, confirming sent the command the session's stage now called for:
/// a charged end_early the rider never agreed to.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

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

  testWidgets(
    'boarding while the cancel sheet is open asks again, sends nothing',
    (tester) async {
      final gate = CancelGate();
      await pumpWaitingWithGate(
        tester,
        rideId: 'waiting-cancel-across-boarding',
        status: RideStatus.driverArriving,
        gate: gate,
      );
      final realtime = AppScope.instance.rideRealtime as MockRideRealtime;
      realtime.holdAssignment();

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Cancel ride?'), findsOneWidget);
      await tester.tap(find.text('Cancel request'));
      await tester.pumpAndSettle();

      // The rider boards while the reason sheet is open.
      realtime.emit(RideStatus.tripStarted, sequence: 2);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      // No request went out on the stale confirmation; the rider is asked
      // again for the stage they are in now.
      expect(gate.sends, 0);
      expect(find.text('End trip here?'), findsOneWidget);
      expect(AppScope.instance.ride.status, RideStatus.tripStarted);
      await tester.tap(find.text('Keep ride'));
      await tester.pumpAndSettle();
      expect(find.byType(WaitingForDriver), findsOneWidget);
    },
  );
}
