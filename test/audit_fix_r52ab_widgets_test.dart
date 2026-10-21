import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/active_ride/presentation/driver_arrived_sheet.dart';
import 'package:movera_rider/features/active_ride/presentation/ride_terminal_state_sheet.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride_geometry.dart';
import 'package:movera_rider/features/active_ride/application/route_change_controller.dart';
import 'package:movera_rider/features/active_ride/presentation/route_change_flow.dart';
import 'package:movera_rider/features/active_ride/presentation/route_change_sheet.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Wave 5 R5.2 parts a+b, on screen: no success text the app did not get.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RideSnapshotStore.epoch = 0;
    AppScope.instance.ride
      ..rideId = null
      // The previous test's ride must not make this one's events stale.
      ..authoritativeVersion = null
      ..authoritativeUpdatedAt = null
      ..suppressRestore = false
      ..restoreFromBackend(RideStatus.idle);
  });

  final ride = RideSnapshot(
    status: RideStatus.driverAssigned,
    savedAt: DateTime(2026, 10, 21),
    pickupAddress: 'Sergels torg 1',
    destinationAddress: 'Odenplan 2',
    pickupLat: 59.3326,
    pickupLng: 18.0649,
    destinationLat: 59.3426,
    destinationLng: 18.0498,
    rideType: 'Movera',
    price: 200,
    paymentMethod: 'Apple Pay',
    rideId: 'r52-ride',
  );

  /// Waiting for a driver on a saved ride (as audit_fix_arrived_sheet_test).
  /// Each call is a new ride, so the shared mock feed starts fresh.
  var rides = 0;
  Future<MockRideRealtime> openWaiting(WidgetTester tester) async {
    final id = 'r52-waiting-${rides++}';
    await RideSnapshotStore.save(
      ride.copyWith(savedAt: DateTime.now(), rideId: id),
    );
    AppScope.instance.ride.restoreFromBackend(
      RideStatus.driverAssigned,
      id: id,
    );
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      home: const Scaffold(body: Center(child: Text('audit-root'))),
    ));
    navigatorKey.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => const WaitingForDriver(
        pickupAddress: 'Sergels torg 1',
        destinationAddress: 'Odenplan 2',
        pickupPosition: LatLng(59.3326, 18.0649),
        destinationPosition: LatLng(59.3426, 18.0498),
        rideType: 'Movera',
        price: 200,
        paymentMethod: 'Apple Pay',
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final realtime = AppScope.instance.rideRealtime as MockRideRealtime;
    realtime.holdAssignment();
    addTearDown(realtime.holdAssignment);
    return realtime;
  }

  /// The driver reaches the pickup and the arrived sheet opens.
  Future<void> driverArrives(
    WidgetTester tester,
    MockRideRealtime realtime,
  ) async {
    realtime.emit(
      RideStatus.driverWaiting,
      signal: RideRealtimeSignal.driverArrived,
      message: 'Driver arrived',
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 250));
    expect(find.byType(DriverArrivedSheet), findsOneWidget);
  }

  /// Pumps a page with one button that runs [open], and taps it.
  Future<void> openFrom(
    WidgetTester tester,
    Future<void> Function(BuildContext context) open,
  ) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => open(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'rider-u36: the sheet shows the server\'s difference, not the device\'s',
      (tester) async {
    // The device still holds 259 kr; the server already charged the earlier
    // (lost) change, so this quote's difference is 0.
    await openFrom(tester, (context) => RouteChangeSheet.confirm(
          context,
          quote: const RouteChangeQuote(
            pickupAddress: 'Sergels torg 1',
            pickupPoint: GeoPoint(59.33, 18.06),
            destinationAddress: 'Arlanda',
            destinationPoint: GeoPoint(59.65, 17.93),
            stops: [],
            oldPriceKr: 259,
            newPriceKr: 308,
            newTotalMinor: 30800,
            differenceMinor: 0,
          ),
          paymentMethod: 'Visa •••• 4242',
        ));
    expect(find.textContaining('49 kr'), findsNothing);
    expect(find.textContaining('charged to'), findsNothing);
  });

  testWidgets('rider-u40: Change route offers no "Set your Home/Work" rows '
      'that cannot do anything', (tester) async {
    // No Home or Work saved on this device.
    await openFrom(tester, (context) => openRouteChange(
          context,
          ride: ride,
          entry: RouteChangeEntry.destination,
          pickupLocked: true,
        ));
    expect(find.text('Set Home'), findsNothing);
    expect(find.text('Set Work'), findsNothing);
  });

  testWidgets('rider-u48: in the trip "Arrive by" follows the live ETA',
      (tester) async {
    final realtime = await openWaiting(tester);
    String arriveBy(int seconds) =>
        'Arrive by ${clockTime(DateTime.now().add(Duration(seconds: seconds)))}';

    realtime.emit(
      RideStatus.tripInProgress,
      latitude: 59.335,
      longitude: 18.06,
      etaSeconds: 600,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Arrive by'), findsWidgets);

    realtime.emit(
      RideStatus.tripInProgress,
      latitude: 59.335,
      longitude: 18.06,
      etaSeconds: 3600,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Arrive by'), findsWidgets);
    expect(find.text(arriveBy(600)), findsNothing,
        reason: 'the sheet must not keep the old arrival time');
  });

  testWidgets('rider-u49: a reload does not open the arrived sheet the '
      'rider already saw', (tester) async {
    final realtime = await openWaiting(tester);
    await driverArrives(tester, realtime);
    final saved = (await RideSnapshotStore.read())!;

    // The page reloads: a fresh Waiting on the same, saved ride.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(MaterialApp(
      home: WaitingForDriver(
        rideId: saved.rideId,
        pickupAddress: 'Sergels torg 1',
        destinationAddress: 'Odenplan 2',
        pickupPosition: const LatLng(59.3326, 18.0649),
        destinationPosition: const LatLng(59.3426, 18.0498),
        rideType: 'Movera',
        price: 200,
        paymentMethod: 'Apple Pay',
      ),
    ));
    await tester.pump();
    realtime.emit(
      RideStatus.driverWaiting,
      latitude: 59.3326,
      longitude: 18.0649,
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 250));

    expect(find.byType(DriverArrivedSheet), findsNothing);
  });

  testWidgets('rider-u47: a no-show closes the arrived sheet and shows the '
      'ended ride', (tester) async {
    final realtime = await openWaiting(tester);
    await driverArrives(tester, realtime);

    realtime.emit(RideStatus.noShow);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byType(DriverArrivedSheet), findsNothing);
    expect(find.byType(RideTerminalStateSheet), findsOneWidget);
  });
}
