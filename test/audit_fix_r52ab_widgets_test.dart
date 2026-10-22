import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
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
import 'package:movera_rider/features/destination_search/presentation/route_picker_page.dart';
import 'package:movera_rider/shared/widgets/custom_google_map.dart';
import 'package:movera_rider/features/home/application/home_places_controller.dart';
import 'package:movera_rider/features/saved_places/presentation/pickup_location.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';
import 'package:movera_rider/features/reservations/presentation/reservation_live_ride.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride_geometry.dart';
import 'package:movera_rider/features/active_ride/application/route_change_controller.dart';
import 'package:movera_rider/features/active_ride/presentation/route_change_flow.dart';
import 'package:movera_rider/features/active_ride/presentation/route_change_sheet.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/shared/widgets/early_input_capture.dart';
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

  /// Where to? with [recent] and [savedPlaces], as Home opens it.
  Future<void> openPicker(
    WidgetTester tester, {
    List<String> recent = const [],
    List<SavedPlaceData> savedPlaces = const [],
  }) =>
      openFrom(tester, (context) => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => RoutePickerPage(
                pickupAddress: 'Sveavägen 1, Stockholm',
                destinationAddress: '',
                stops: const [],
                stopsSupported: true,
                initialField: 'destination',
                capture: EarlyInputCapture(),
                here: const GeoPoint(59.33, 18.06),
                homeAddress: null,
                workAddress: null,
                savedPlaces: savedPlaces,
                recent: recent,
                onPickOnMap: ({required pickup, required address}) async =>
                    null,
                onFinish: (_) async => null,
              ),
            ),
          ));

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

  testWidgets('rider-u55: a scheduled ride\'s live page offers no route '
      'change it can never apply', (tester) async {
    // As audit_fix_live_cancel_terms_test: a reservation whose driver is
    // on the way.
    final now = DateTime(2026, 10, 21, 23, 20);
    final controller = ReservationController(
      store: LocalReservationRepository(
        storage: MemoryReservationStorage(),
        nextId: () => 'rsv-r52',
      ),
      clock: () => now,
    );
    addTearDown(controller.dispose);
    final created = await controller.create(ReservationDraft(
      scheduledPickupAt: DateTime(2026, 10, 21, 23, 50),
      pickup: const ReservationPlace(label: 'Home', lat: 59.33, lng: 18.06),
      destination:
          const ReservationPlace(label: 'Arlanda', lat: 59.65, lng: 17.93),
      categoryId: 'comfort',
      categoryName: 'Comfort',
      categoryImage: 'assets/images/rides/comfort.webp',
      price: 450,
      paymentMethod: 'Cash',
    ));
    await controller.assignMockDriver(
      created.reservationId,
      driver: const ReservationDriver(firstName: 'Amina', rating: 4.9),
    );
    final live = await controller.update(
      created.reservationId,
      const ReservationPatch(status: ReservationStatus.driverEnRoute),
    );
    await tester.pumpWidget(MaterialApp(
      home: ReservationLiveRide.pageFor(live, controller: controller),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(WaitingForDriver), findsOneWidget);
    expect(find.byIcon(Icons.more_horiz_rounded), findsNothing);
  });

  testWidgets('rider-u59: the map rebuilt after Change route shows the car '
      'at its last fix', (tester) async {
    final realtime = await openWaiting(tester);
    realtime.emit(
      RideStatus.driverArriving,
      latitude: 59.3340,
      longitude: 18.0600,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    Iterable<Marker> cars() => tester
        .widget<CustomGoogleMap>(find.byKey(const ValueKey('waiting-map')))
        .markers!
        .where((marker) => marker.markerId.value == 'driver');

    // Change route parks the map; backing out of it builds a new one, and
    // the driver (standing still) sends no new fix.
    await tester.tap(find.byIcon(Icons.more_horiz_rounded).first);
    await tester.pumpAndSettle(const Duration(milliseconds: 250));
    expect(find.byType(RoutePickerPage), findsOneWidget);
    Navigator.of(tester.element(find.byType(RoutePickerPage))).pop();
    await tester.pumpAndSettle(const Duration(milliseconds: 250));

    expect(cars(), hasLength(1));
    expect(cars().single.position, const LatLng(59.3340, 18.0600));
  });

  testWidgets('rider-u82: a saved-place search that could not run says '
      'so, not "address not found"', (tester) async {
    // As phase100_destination_input_test's pumpSearch.
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (_, __) => MaterialApp(
        home: RiderSearchPickupLocation(
          geocode: (_) async => throw TimeoutException('offline'),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Kungsgatan 4');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.text("Couldn't reach Movera. Check your connection."),
        findsOneWidget);
  });

  testWidgets('rider-u91: a place the rider named shows that name in '
      'Where to?', (tester) async {
    await openPicker(tester, savedPlaces: const [
      SavedPlaceData(
        title: 'Mamma',
        type: 'mamma',
        address: 'Götgatan 1, Stockholm',
      ),
    ]);
    expect(find.text('Mamma'), findsOneWidget);
    expect(find.text('Other'), findsNothing);
  });

  testWidgets('rider-u92: a recent with a longer house number does not '
      'hide the address typed', (tester) async {
    await openPicker(tester, recent: const ['Drottninggatan 50, Stockholm']);
    final field = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == 'Where to?',
    );
    await tester.enterText(field, 'Drottninggatan 5');
    // As audit_fix_route_picker_test: the in-process backend answers on a
    // real clock, so wait for its suggestions (bounded).
    final suggestion = find.byIcon(Icons.location_on_outlined);
    for (var i = 0; i < 100 && suggestion.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      // rider-u86: the request waits for a pause in typing (fake time).
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(suggestion, findsWidgets,
        reason: "'Drottninggatan 5' is not the recent 'Drottninggatan 50'");
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
