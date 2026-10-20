import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/matched_driver.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Driver on the way: low stop is one compact row, the full stop ends where
/// the content ends, and the recenter button rides on the sheet.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RideSnapshotStore.epoch = 0;
    AppScope.instance.ride
      ..rideId = null
      ..suppressRestore = false
      ..restoreFromBackend(RideStatus.idle);
  });

  const driver = MatchedDriver(
    id: 'd1',
    firstName: 'Johan',
    rating: 4.8,
    tripCount: 1685,
    vehicleMake: 'Volvo',
    vehicleModel: 'V60',
    vehicleColor: 'Grey',
    plate: 'MVR 771',
  );

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    AppScope.instance.ride.restoreFromBackend(
      RideStatus.driverAssigned,
      id: 'waiting-motion',
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: WaitingForDriver(
          pickupAddress: 'Stockholm pickup',
          destinationAddress: 'Stockholm destination',
          pickupPosition: LatLng(59.3293, 18.0686),
          destinationPosition: LatLng(59.3326, 18.0649),
          rideType: 'Movera',
          price: 259,
          paymentMethod: 'Cash',
          driver: driver,
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    // The demo driver feed assigns a driver after 25 s; let it run out.
    await tester.pump(const Duration(seconds: 30));
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  double sheetTop(WidgetTester tester) =>
      tester.getTopLeft(find.byKey(const ValueKey('waiting-panel'))).dy;

  testWidgets('low stop shows one compact row with ETA, driver and plate', (
    tester,
  ) async {
    await open(tester);
    expect(find.byKey(const ValueKey('waiting-compact-row')), findsNothing);
    await tester.fling(
      find.byKey(const ValueKey('waiting-panel')),
      const Offset(0, 400),
      1200,
    );
    await settle(tester);
    final row = find.byKey(const ValueKey('waiting-compact-row'));
    expect(row, findsOneWidget);
    expect(
      find.descendant(of: row, matching: find.text('MVR 771')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.textContaining('Johan')),
      findsOneWidget,
    );
    // Nothing of the compact row is cut by the screen edge.
    expect(tester.getBottomLeft(row).dy, lessThanOrEqualTo(844));

    await tester.tap(row);
    await settle(tester);
    expect(find.byKey(const ValueKey('waiting-compact-row')), findsNothing);
    await close(tester);
  });

  testWidgets('full stop ends where the content ends', (tester) async {
    await open(tester);
    final middle = sheetTop(tester);
    await tester.fling(
      find.byKey(const ValueKey('waiting-panel')),
      const Offset(0, -500),
      1500,
    );
    await settle(tester);
    final full = sheetTop(tester);
    expect(full, lessThan(middle));
    // Not pinned under the status bar: the map still shows above it.
    expect(full, greaterThan(80));
    // The recenter button is gone while the sheet is fully up.
    final fade = tester.widget<Opacity>(
      find
          .ancestor(
            of: find.bySemanticsLabel('Recenter map'),
            matching: find.byType(Opacity),
          )
          .first,
    );
    expect(fade.opacity, 0);
    await close(tester);
  });

  testWidgets('recenter button rides on top of the sheet', (tester) async {
    await open(tester);
    final button = find.bySemanticsLabel('Recenter map');
    final before = tester.getBottomLeft(button).dy;
    expect(before, lessThan(sheetTop(tester)));
    await tester.fling(
      find.byKey(const ValueKey('waiting-panel')),
      const Offset(0, 400),
      1200,
    );
    await settle(tester);
    final after = tester.getBottomLeft(button).dy;
    expect(after, greaterThan(before));
    expect(after, lessThan(sheetTop(tester)));
    await close(tester);
  });
}
