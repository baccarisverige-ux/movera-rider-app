import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/navigator_key.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/home/presentation/home.dart';
import 'package:movera_rider/features/home/presentation/widgets/where_to_card.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/presentation/ride_scheduled.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The platform side of Home's LocationRepository: location allowed, a fix
/// at [lat]/[lng], and a live stream the test moves by hand.
class _FakeGeolocator extends GeolocatorPlatform {
  _FakeGeolocator(this.lat, this.lng);

  double lat;
  double lng;
  int currentPositionCalls = 0;
  final StreamController<Position> live = StreamController.broadcast();

  /// Fix timestamps advance a second per fix, as a walking rider's would.
  DateTime clock = DateTime(2026, 10, 1, 12);

  Position get position => Position(
    latitude: lat,
    longitude: lng,
    timestamp: clock,
    accuracy: 4,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );

  void moveTo(double newLat, double newLng) {
    lat = newLat;
    lng = newLng;
    clock = clock.add(const Duration(seconds: 1));
    live.add(position);
  }

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.whileInUse;

  @override
  Future<LocationPermission> requestPermission() async =>
      LocationPermission.whileInUse;

  @override
  Future<Position?> getLastKnownPosition({
    bool forceLocationManager = false,
  }) async => null;

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    currentPositionCalls += 1;
    return position;
  }

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) =>
      live.stream;
}

/// Owner video 16:35 (finder B10): after Book later -> "Your ride is
/// scheduled" -> Done, Home's "Where to?" kept the booked destination
/// (Stockholm Arlanda Airport). Home cleared it only when a ride-now ride
/// ended or was cancelled in the flow (home_route_flow.dart,
/// _withParkedHomeMap), never when the flow scheduled a ride.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  late GeolocatorPlatform original;
  late _FakeGeolocator gps;
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FindingDriverController.active = null;
    AppScope.instance.ride
      ..rideId = null
      ..status = RideStatus.idle
      ..suppressRestore = false
      ..authoritativeVersion = null
      ..authoritativeUpdatedAt = null;
    original = GeolocatorPlatform.instance;
    gps = _FakeGeolocator(59.3293, 18.0686);
    GeolocatorPlatform.instance = gps;
  });
  tearDown(() => GeolocatorPlatform.instance = original);

  Future<void> frames(WidgetTester tester, int count, {int ms = 100}) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(Duration(milliseconds: ms));
    }
  }

  testWidgets('after a ride is scheduled, Home shows "Where to?" again', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) =>
            MaterialApp(navigatorKey: moveraNavigatorKey, home: const Home()),
      ),
    );
    await frames(tester, 8);
    for (var i = 0; i < 5 && !gps.live.hasListener; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await frames(tester, 2);
    }

    await tester.tap(find.text('Where to?'));
    for (
      var i = 0;
      i < 40 && find.byType(TextField).evaluate().length < 2;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 450));
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Stockholm Central');
    await tester.pump();
    await tester.enterText(fields.at(1), 'Arlanda Airport');
    await tester.pump();
    var pick = find.textContaining(
      'Stockholm Arlanda Airport',
      findRichText: true,
    );
    for (var i = 0; i < 30 && pick.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      pick = find.textContaining(
        'Stockholm Arlanda Airport',
        findRichText: true,
      );
    }
    await tester.tap(pick.first);
    for (var i = 0; i < 30 && find.byType(SelectRide).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(SelectRide), findsOneWidget);

    // Book for later succeeded on the categories screen: it hands the new
    // booked ride to Home's flow, which shows "Your ride is scheduled".
    final booked = await tester.runAsync(
      () => AppScope.instance.reservations.create(
        ReservationDraft(
          scheduledPickupAt: DateTime.now().add(const Duration(days: 1)),
          pickup: const ReservationPlace(
            label: 'Stockholm Central',
            lat: 59.3300,
            lng: 18.0590,
          ),
          destination: const ReservationPlace(
            label: 'Stockholm Arlanda Airport',
            lat: 59.6519,
            lng: 17.9186,
          ),
          categoryId: 'economy',
          categoryName: 'Movera',
          categoryImage: '',
          price: 549,
          paymentMethod: 'cash',
        ),
      ),
    );
    final select = tester.widget<SelectRide>(find.byType(SelectRide));
    unawaited(
      select.onScheduled!(
        tester.element(find.byType(SelectRide)),
        booked!.reservationId,
      ),
    );
    await frames(tester, 10);
    expect(find.byType(RideScheduledPage), findsOneWidget);
    await tester.tap(find.text('Done'));
    await frames(tester, 20);
    expect(find.byType(RideScheduledPage), findsNothing);

    final card = find.byType(WhereToCard);
    expect(card, findsOneWidget);
    expect(
      find.descendant(
        of: card,
        matching: find.textContaining('Arlanda', findRichText: true),
      ),
      findsNothing,
      reason: 'Home kept the booked destination',
    );
    expect(
      find.descendant(of: card, matching: find.text('Where to?')),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 10));
    debugDefaultTargetPlatformOverride = null;
  });
}
