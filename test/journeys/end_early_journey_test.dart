import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/navigator_key.dart';
import 'package:movera_rider/app/screen_scale.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/active_ride/presentation/driver_arrived_sheet.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/destination_search/presentation/route_picker_page.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/presentation/finding_drivers.dart';
import 'package:movera_rider/features/history/data/on_demand_ride_history_store.dart';
import 'package:movera_rider/features/home/presentation/home.dart';
import 'package:movera_rider/features/pickup/presentation/set_pickup_page.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_complete/data/last_completed_ride.dart';
import 'package:movera_rider/features/ride_complete/presentation/ride_completed.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// R-UI UI-01 (audit flow F3): Book now → driver → on board → "End trip".
/// It used to say only "Cancelling will end this ride and return you to
/// Home", send end-early, and drop the rider on Home with no amount, no
/// receipt. Now the sheet says they pay for the distance driven and the trip
/// ends on its summary.
Future<void> _waitFor(WidgetTester t, Finder f, {int tries = 50}) async {
  for (var i = 0; i < tries && f.evaluate().isEmpty; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    RideSnapshotStore.epoch = 0;
    LastCompletedRide.clear();
  });

  testWidgets('ending the trip on board shows the summary, not Home', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    FindingDriverController.active = null;
    AppScope.instance.ride
      ..rideId = null
      ..status = RideStatus.idle
      ..suppressRestore = false
      ..authoritativeVersion = null
      ..authoritativeUpdatedAt = null;
    await tester.pumpWidget(
      MoveraScreenUtilInit(
        builder: (_, __) =>
            MaterialApp(navigatorKey: moveraNavigatorKey, home: const Home()),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Home → Plan your ride → destination → Select ride → Set pickup.
    await tester.tap(find.text('Where to?'));
    await _waitFor(tester, find.byType(RoutePickerPage));
    await tester.pump(const Duration(milliseconds: 450));
    await tester.enterText(find.byType(TextField).at(0), 'Stockholm Central');
    await tester.pump();
    await tester.enterText(find.byType(TextField).last, 'Arlanda Airport');
    await tester.pump();
    final pick = find.textContaining(
      'Stockholm Arlanda Airport',
      findRichText: true,
    );
    await _waitFor(tester, pick, tries: 30);
    await tester.tap(pick.first);
    await _waitFor(tester, find.byType(SelectRide), tries: 40);
    final select = find.text('Select Movera');
    await _waitFor(tester, select, tries: 40);
    await tester.ensureVisible(select);
    await tester.tap(select);
    await _waitFor(tester, find.byType(SetPickupPage), tries: 40);
    // P5-R6: Set pickup finishes opening before the rider confirms (a tap
    // while it slides in is the second tap of a double tap and is ignored).
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Confirm and search'));
    await _waitFor(tester, find.byType(FindingDrivers), tries: 40);

    // Driver, pickup, on board.
    final mock = AppScope.instance.rideRealtime as MockRideRealtime;
    addTearDown(mock.unsubscribe);
    mock.assignNow();
    await _waitFor(tester, find.byType(WaitingForDriver));
    mock.markArrivedForTest();
    await _waitFor(tester, find.byType(DriverArrivedSheet), tries: 20);
    await tester.pump(const Duration(milliseconds: 350));
    final onTheWay = find.text("I'm on the way");
    if (onTheWay.evaluate().isNotEmpty) {
      await tester.ensureVisible(onTheWay);
      await tester.tap(onTheWay);
    }
    for (
      var i = 0;
      i < 20 && find.byType(DriverArrivedSheet).evaluate().isNotEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(seconds: 9));
    await tester.pump(const Duration(seconds: 3));
    expect(AppScope.instance.ride.status, RideStatus.tripInProgress);

    await tester.tap(find.bySemanticsLabel('End trip').first);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('End trip here?'), findsOneWidget);
    expect(find.textContaining('pay for the distance driven'), findsWidgets);
    expect(find.textContaining('return you to Home'), findsNothing);

    await tester.tap(find.text('End trip here').last);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Why are you ending the trip?'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await _waitFor(tester, find.byType(RideCompleted), tries: 60);

    expect(find.byType(RideCompleted), findsOneWidget);
    expect(find.text('Trip ended early'), findsOneWidget);
    expect(find.byType(Home), findsNothing);
    expect(AppScope.instance.ride.status, RideStatus.cancelledByRider);
    final record = (await tester.runAsync(
      OnDemandRideHistoryStore.read,
    ))!.single;
    expect(record.endedEarly, isTrue);

    await tester.tap(find.byKey(const ValueKey('ride-completed-done')));
    await _waitFor(tester, find.byType(Home), tries: 40);
    expect(find.byType(RideCompleted), findsNothing);
    mock.unsubscribe();
    await tester.pump();
    debugDefaultTargetPlatformOverride = null;
  });
}
