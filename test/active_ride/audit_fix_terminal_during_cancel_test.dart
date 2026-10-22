import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/active_ride/presentation/ride_terminal_state_sheet.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'audit_fix_cancel_in_flight_harness.dart';

/// rider-u50: while a Waiting cancel was in flight, `_leaving` was true and
/// a terminal status arriving on realtime was dropped before it was
/// queued. When the server then refused the cancel (409: the ride already
/// ended) the flags were reset but nothing replayed the status, so Waiting
/// stayed on a ride that was over; for noShow or cancelledByAdmin no
/// further tick ever came.
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
    'a no-show that lands during a refused cancel still ends Waiting',
    (tester) async {
      final gate = CancelGate();
      await pumpWaitingWithGate(
        tester,
        rideId: 'waiting-noshow-during-cancel',
        status: RideStatus.driverArriving,
        gate: gate,
      );
      await confirmCancel(tester, gate);

      // The driver gives up on the rider while the cancel is out.
      final realtime = AppScope.instance.rideRealtime as MockRideRealtime;
      realtime.emit(RideStatus.noShow, sequence: 2);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // The server refuses: the ride already ended.
      gate.answer(409, {'code': 'invalid_transition'});
      await tester.pump();
      await tester.pumpAndSettle(const Duration(milliseconds: 600));

      expect(find.byType(RideTerminalStateSheet), findsOneWidget);
      expect(AppScope.instance.ride.status, RideStatus.noShow);
      expect(await RideSnapshotStore.read(), isNull);

      await tester.tap(
        find.byKey(const ValueKey<String>('ride-terminal-acknowledge')),
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      expect(find.byType(WaitingForDriver), findsNothing);
      expect(find.text('audit-root'), findsOneWidget);
    },
  );
}
