import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/finding_driver/presentation/cancel_ride_sheet.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'audit_fix_cancel_in_flight_harness.dart';

/// G26-back, owner decision 2026-11-12 "Nothing / collapse" (contract
/// v0.18.73 `contract.json#riderBack`): Android back on
/// the "driver is coming" screen before pickup never opens the cancel flow
/// (one tap from a paid cancel). It lowers the sheet when it is fully up,
/// and otherwise does nothing; the screen stays. Cancel is the close (X)
/// button only.
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

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> frames(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Leaves the screen and lets its timers run out.
  Future<void> leave(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(minutes: 2));
  }

  final panel = find.byKey(const ValueKey<String>('waiting-panel'));
  double panelTop(WidgetTester tester) => tester.getTopLeft(panel).dy;

  void expectNoCancelFlow(CancelGate gate) {
    expect(find.text('Cancel ride?'), findsNothing);
    expect(find.byType(CancelRideSheet), findsNothing);
    expect(find.byType(WaitingForDriver), findsOneWidget);
    expect(find.text('audit-root'), findsNothing);
    expect(gate.sends, 0);
    expect(AppScope.instance.ride.status, RideStatus.driverArriving);
  }

  testWidgets(
    'Android back on Waiting before pickup does not open Cancel ride?',
    (tester) async {
      phone(tester);
      final gate = CancelGate();
      await pumpWaitingWithGate(
        tester,
        rideId: 'g26-back-resting',
        status: RideStatus.driverArriving,
        gate: gate,
      );
      await frames(tester);
      final resting = panelTop(tester);

      await tester.binding.handlePopRoute();
      await frames(tester);

      expectNoCancelFlow(gate);
      // Nothing moved: the sheet stays where it rested.
      expect(panelTop(tester), moreOrLessEquals(resting, epsilon: 1));

      // A second back is still nothing.
      await tester.binding.handlePopRoute();
      await frames(tester);
      expectNoCancelFlow(gate);
      await leave(tester);
    },
  );

  testWidgets('Android back on Waiting lowers a fully raised sheet', (
    tester,
  ) async {
    phone(tester);
    final gate = CancelGate();
    await pumpWaitingWithGate(
      tester,
      rideId: 'g26-back-raised',
      status: RideStatus.driverArriving,
      gate: gate,
    );
    await frames(tester);
    final resting = panelTop(tester);

    await tester.drag(panel, const Offset(0, -500));
    await frames(tester);
    final raised = panelTop(tester);
    expect(raised, lessThan(resting - 24), reason: 'the sheet is fully up');

    await tester.binding.handlePopRoute();
    await frames(tester);

    expectNoCancelFlow(gate);
    expect(panelTop(tester), moreOrLessEquals(resting, epsilon: 1));
    await leave(tester);
  });

  testWidgets('the close (X) button still opens Cancel ride?', (tester) async {
    phone(tester);
    final gate = CancelGate();
    await pumpWaitingWithGate(
      tester,
      rideId: 'g26-close-still-cancels',
      status: RideStatus.driverArriving,
      gate: gate,
    );
    await frames(tester);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await frames(tester);

    expect(find.byType(CancelRideSheet), findsOneWidget);
    expect(find.text('Cancel ride?'), findsOneWidget);
    expect(gate.sends, 0);
    await leave(tester);
  });
}
