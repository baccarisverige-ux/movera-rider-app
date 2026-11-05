import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/navigator_key.dart';
import 'package:movera_rider/app/router/routes.dart';
import 'package:movera_rider/core/config/zone_clock.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/presentation/finding_drivers.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';
import 'package:movera_rider/features/reservations/presentation/plan_return_ride.dart';
import 'package:movera_rider/features/ride_booking/data/mock_quote_repository.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/quote.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// B16 (2026-11-04): Select ride behaviour that replaces source-reading
/// guards (archived in Rules/archive/old-tests/movera-rider-app/).

/// The server's quote: an odd price per category that no list table has.
class _ServerQuotes implements QuoteRepository {
  static const prices = {'economy': 31700, 'comfort': 41300};

  @override
  Future<RideQuote> quote({
    required String rideType,
    required int distanceMeters,
    int durationSeconds = 600,
    String? pickup,
    String? destination,
    GeoPoint? pickupPoint,
    GeoPoint? destinationPoint,
    List<RouteStop> stops = const <RouteStop>[],
  }) => Future<RideQuote>.value(
    RideQuote(
      id: 'q-$rideType',
      rideType: rideType,
      totalMinor: prices[rideType] ?? 52300,
      currency: 'SEK',
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      signedPayload: 'sig',
    ),
  );
}

Reservation _origin() {
  final at = ZoneClock.toUtc(
    DateTime.now().add(const Duration(days: 2)),
    ZoneClock.stockholm,
  );
  return Reservation(
    reservationId: 'rsv_b16_origin',
    createdAt: at.subtract(const Duration(days: 1)),
    scheduledPickupAt: at,
    timeZone: ZoneClock.stockholm,
    pickup: const ReservationPlace(
      label: 'Klockarvägen 37',
      lat: 59.19,
      lng: 17.62,
    ),
    destination: const ReservationPlace(
      label: 'Arlanda Express',
      lat: 59.65,
      lng: 17.93,
    ),
    categoryId: 'economy',
    categoryName: 'Movera',
    categoryImage: 'assets/images/rides/movera.webp',
    price: 522,
    paymentMethod: 'Cash',
    status: ReservationStatus.scheduled,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FindingDriverController.active = null;
    AppScope.instance.ride
      ..rideId = null
      ..status = RideStatus.idle;
    AppScope.instance.promotion.value = null;
  });

  Future<void> host(WidgetTester tester, Widget page, {String? name}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        minTextAdapt: true,
        splitScreenMode: true,
        builder: (_, __) => MaterialApp(
          navigatorKey: moveraNavigatorKey,
          home: const Scaffold(body: Text('b16-home')),
        ),
      ),
    );
    moveraNavigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        settings: RouteSettings(name: name),
        builder: (_) => page,
      ),
    );
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<RideSelectionController> openSelectRide(WidgetTester tester) async {
    final selection = RideSelectionController(quotes: _ServerQuotes());
    addTearDown(selection.dispose);
    await host(
      tester,
      SelectRide(
        pickupAddress: 'Stockholm Central',
        destinationAddress: 'Odenplan',
        pickupPosition: const LatLng(59.3293, 18.0686),
        destinationPosition: const LatLng(59.3429, 18.0496),
        pickupAlreadyConfirmed: true,
        selection: selection,
      ),
      name: AppRoutes.selectRide,
    );
    return selection;
  }

  testWidgets('categories show the server quote, never a catalog fare table', (
    tester,
  ) async {
    await openSelectRide(tester);
    final rows = find.descendant(
      of: find.byType(SelectRide),
      matching: find.textContaining('317', findRichText: true),
    );
    expect(rows, findsWidgets);
    expect(
      find.descendant(
        of: find.byType(SelectRide),
        matching: find.textContaining('259', findRichText: true),
      ),
      findsNothing,
    );
    // No promotion from the server: no invented promotion either.
    expect(AppScope.instance.promotion.active, isNull);
    expect(find.textContaining(RegExp(r'\d+% off')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the selected category lives in the selection controller and '
      'the map sits above the sheet', (tester) async {
    final selection = await openSelectRide(tester);
    expect(selection.selectedRideId, 'economy');
    final comfort = find.descendant(
      of: find.byType(SelectRide),
      matching: find.textContaining('413', findRichText: true),
    );
    expect(comfort, findsWidgets);
    await tester.ensureVisible(comfort.first);
    await tester.tap(comfort.first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(selection.selectedRideId, 'comfort');
    expect(find.text('Select Comfort'), findsOneWidget);
    expect(find.byKey(const ValueKey('select-ride-map')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a return ride opens the shared category selector in '
      'scheduled mode, with the trip reversed', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      var n = 0;
      final reservations = ReservationController(
        store: LocalReservationRepository(
          storage: MemoryReservationStorage(),
          nextId: () => 'rsv_b16_${++n}',
        ),
      );
      await host(
        tester,
        PlanReturnRidePage(origin: _origin(), controller: reservations),
      );
      final select = find.byType(SelectRide);
      expect(select, findsOneWidget);
      final widget = tester.widget<SelectRide>(select);
      expect(widget.pickupAddress, 'Arlanda Express');
      expect(widget.destinationAddress, 'Klockarvägen 37');
      final cta = find.text('Schedule Movera');
      for (var i = 0; i < 60 && cta.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(cta, findsOneWidget);
      expect(find.text('Select Movera'), findsNothing);
      expect(find.byType(FindingDrivers), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
