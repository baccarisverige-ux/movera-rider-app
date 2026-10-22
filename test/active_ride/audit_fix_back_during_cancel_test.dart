import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'audit_fix_cancel_in_flight_harness.dart';

/// rider-29: `_leaving` was set before the cancel request was sent and
/// PopScope used it as canPop, so a system back during the "Cancelling…"
/// card popped Waiting with the request still out. The outcome was then
/// dropped on `!mounted`: a confirmed cancel never went Home, a refused one
/// left the ride with no screen, and Finding underneath stayed parked.
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
    'back during an in-flight cancel keeps Waiting until the answer',
    (tester) async {
      final gate = CancelGate();
      await pumpWaitingWithGate(
        tester,
        rideId: 'waiting-back-during-cancel',
        status: RideStatus.driverArriving,
        gate: gate,
      );
      (AppScope.instance.rideRealtime as MockRideRealtime).holdAssignment();
      await confirmCancel(tester, gate);

      await tester.binding.handlePopRoute();
      // Fixed frames, not pumpAndSettle: the "Cancelling…" card animates,
      // and settling it would run the fake clock past the API timeout.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.byType(WaitingForDriver), findsOneWidget);
      expect(find.text('audit-root'), findsNothing);
      expect(gate.inFlight, isTrue);

      gate.answer(200, {
        'code': 'OK',
        'ride': {
          'tripId': 'waiting-back-during-cancel',
          'status': 'cancelled_by_rider',
        },
      });
      await tester.pump();
      await tester.pumpAndSettle(const Duration(milliseconds: 600));

      expect(AppScope.instance.ride.status, RideStatus.cancelledByRider);
      expect(find.byType(WaitingForDriver), findsNothing);
      expect(find.text('audit-root'), findsOneWidget);
      expect(await RideSnapshotStore.read(), isNull);
    },
  );
}
