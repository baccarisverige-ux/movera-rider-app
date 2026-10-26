import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/shared/widgets/custom_google_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/navigator_key.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/active_ride/presentation/ride_terminal_state_sheet.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/finding_driver/presentation/finding_drivers.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// N10 (owner, 2026-10-26: "only add Search again"): the end sheet after a
/// no-show or a driver's end offers "Search again" first and "Back to home"
/// second; Search again books the same trip again and opens the search.

const _pickup = LatLng(59.3293, 18.0686);
const _destination = LatLng(59.3326, 18.0649);

RideSnapshot _snapshot(String rideId) => RideSnapshot(
  status: RideStatus.driverAssigned,
  savedAt: DateTime.now(),
  pickupAddress: 'Stockholm pickup',
  destinationAddress: 'Solna centrum, 171 45 Solna',
  pickupLat: _pickup.latitude,
  pickupLng: _pickup.longitude,
  destinationLat: _destination.latitude,
  destinationLng: _destination.longitude,
  rideType: 'Movera',
  price: 259,
  paymentMethod: 'Cash',
  rideId: rideId,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  setUp(() {
    // No native map view in a widget test: a blank one that never starts.
    final maps = GoogleMapsFlutterPlatform.instance;
    GoogleMapsFlutterPlatform.instance = _BlankMaps();
    addTearDown(() => GoogleMapsFlutterPlatform.instance = maps);
    SharedPreferences.setMockInitialValues({});
    RideSnapshotStore.epoch = 0;
    AppScope.instance.ride
      ..rideId = null
      ..suppressRestore = false
      ..authoritativeVersion = null
      ..authoritativeUpdatedAt = null
      ..restoreFromBackend(RideStatus.idle);
  });

  Future<MockRideRealtime> pumpTrip(
    WidgetTester tester,
    String rideId,
    List<RideStatus> steps,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await RideSnapshotStore.save(_snapshot(rideId));
    AppScope.instance.ride
      ..restoreFromBackend(RideStatus.driverAssigned, id: rideId)
      ..bookedCategoryId = 'economy'
      ..bookedPaymentMethodId = 'cash';
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        minTextAdapt: true,
        splitScreenMode: true,
        builder: (_, __) => MaterialApp(
          navigatorKey: moveraNavigatorKey,
          home: const Scaffold(body: Center(child: Text('home root'))),
        ),
      ),
    );
    moveraNavigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const WaitingForDriver(
          pickupAddress: 'Stockholm pickup',
          destinationAddress: 'Solna centrum, 171 45 Solna',
          pickupPosition: _pickup,
          destinationPosition: _destination,
          rideType: 'Movera',
          price: 259,
          paymentMethod: 'Cash',
          categoryId: 'economy',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final realtime = AppScope.instance.rideRealtime as MockRideRealtime;
    realtime.holdAssignment();
    for (final step in steps) {
      realtime.emit(step, latitude: _pickup.latitude, longitude: _pickup.longitude);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }
    return realtime;
  }

  Future<void> frames(WidgetTester tester, [int count = 12]) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  testWidgets('after a no-show: "Search again" first, "Back to home" second; '
      'Back to home goes Home', (tester) async {
    final realtime = await pumpTrip(tester, 'n10-no-show', [
      RideStatus.driverArriving,
      RideStatus.driverWaiting,
    ]);
    realtime.emit(RideStatus.noShow);
    await frames(tester);
    expect(find.byKey(const ValueKey<String>('ride-terminal-state-noShow')),
        findsOneWidget);
    expect(find.text('Search again'), findsOneWidget);
    expect(find.text('Back to home'), findsOneWidget);
    // Search again is the main (first) button.
    expect(
      tester.getTopLeft(find.text('Search again')).dy,
      lessThan(tester.getTopLeft(find.text('Back to home')).dy),
    );
    await tester.tap(find.text('Back to home'));
    await frames(tester, 20);
    expect(find.byType(WaitingForDriver), findsNothing);
    expect(find.byType(FindingDrivers), findsNothing);
    expect(find.text('home root'), findsOneWidget);
  });

  testWidgets('after a no-show, Search again books the same trip and opens '
      'the search', (tester) async {
    final realtime = await pumpTrip(tester, 'n10-again', [
      RideStatus.driverArriving,
      RideStatus.driverWaiting,
    ]);
    realtime.emit(RideStatus.noShow);
    await frames(tester);
    await tester.tap(find.text('Search again'));
    // The booking goes through the app's in-process API: let it run.
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    // A price other than the one shown is asked first.
    final accept = find.byKey(const ValueKey('rebook-price-accept'));
    if (accept.evaluate().isNotEmpty) {
      await tester.tap(accept);
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
    expect(find.byType(WaitingForDriver), findsNothing);
    final finding = tester.widget<FindingDrivers>(find.byType(FindingDrivers));
    expect(finding.pickupAddress, 'Stockholm pickup');
    expect(finding.destinationAddress, 'Solna centrum, 171 45 Solna');
    expect(finding.rideType, 'Movera');
    expect(finding.paymentMethod, 'Cash');
    expect(AppScope.instance.ride.rideId, isNot('n10-again'));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('after the driver ends the trip on board the sheet also '
      'offers Search again', (tester) async {
    final realtime = await pumpTrip(tester, 'n10-ended', [
      RideStatus.driverArriving,
      RideStatus.driverWaiting,
      RideStatus.tripStarted,
      RideStatus.tripInProgress,
    ]);
    realtime.emit(RideStatus.endedByDriver,
        latitude: _destination.latitude, longitude: _destination.longitude);
    await frames(tester, 20);
    expect(find.byKey(const ValueKey<String>('ride-terminal-state-endedByDriver')),
        findsOneWidget);
    expect(find.text('Search again'), findsOneWidget);
    expect(find.text('Back to home'), findsOneWidget);
    // Search again starts where the car stopped, not at the old pickup.
    await tester.tap(find.text('Search again'));
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    final accept = find.byKey(const ValueKey('rebook-price-accept'));
    if (accept.evaluate().isNotEmpty) {
      await tester.tap(accept);
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
    final finding = tester.widget<FindingDrivers>(find.byType(FindingDrivers));
    expect(finding.pickupPosition, _destination);
    expect(finding.destinationAddress, 'Solna centrum, 171 45 Solna');
    await tester.pumpWidget(const SizedBox());
  });

  // Owner N6: the trip map reads the route from above (no tilt with zoom).
  testWidgets('N6: the trip map stays flat', (tester) async {
    await pumpTrip(tester, 'n6-trip-map', [RideStatus.driverArriving]);
    final maps = find.byType(CustomGoogleMap);
    expect(maps, findsWidgets);
    for (final map in tester.widgetList<CustomGoogleMap>(maps)) {
      expect(map.tiltWithZoom, isFalse);
    }
    await tester.pumpWidget(const SizedBox());
  });

  test('only a no-show and a driver end offer Search again', () {
    for (final status in RideStatus.values) {
      expect(canSearchAgainAfter(status),
          status == RideStatus.noShow || status == RideStatus.endedByDriver,
          reason: status.name);
    }
  });
}

class _BlankMaps extends GoogleMapsFlutterPlatform {
  @override
  Future<void> init(int mapId) async {}

  @override
  Widget buildViewWithConfiguration(
    int creationId,
    PlatformViewCreatedCallback onPlatformViewCreated, {
    required MapWidgetConfiguration widgetConfiguration,
    MapConfiguration mapConfiguration = const MapConfiguration(),
    MapObjects mapObjects = const MapObjects(),
  }) =>
      const SizedBox.expand();

  @override
  void dispose({required int mapId}) {}
}
