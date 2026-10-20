import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/navigator_key.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/home/presentation/home.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/shared/widgets/custom_google_map.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// NAV-3: Home's map is parked whenever another map screen covers it, not only
/// for the flows home.dart opens itself. Two Google Maps at once crashes the
/// browser tab on Flutter web.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  int mapsMounted() =>
      find.byType(CustomGoogleMap, skipOffstage: false).evaluate().length;

  testWidgets('a scheduled ride going live from Home never mounts a second '
      'map', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    FindingDriverController.active = null;
    AppScope.instance.ride
      ..rideId = null
      ..status = RideStatus.idle
      ..suppressRestore = false
      ..authoritativeVersion = null
      ..authoritativeUpdatedAt = null;

    // A reservation whose driver is already on the way: the Home chrono
    // opens its live ride (a map screen) on its own, with no tap.
    final reservations = AppScope.instance.reservations;
    late Reservation ride;
    await tester.runAsync(() async {
      await reservations.hydrate();
      ride = await reservations.create(
        ReservationDraft(
          scheduledPickupAt: DateTime.now().add(const Duration(hours: 1)),
          pickup: const ReservationPlace(
            label: 'Stockholm Central',
            lat: 59.3293,
            lng: 18.0686,
          ),
          destination: const ReservationPlace(
            label: 'Arlanda Airport',
            lat: 59.6519,
            lng: 17.9186,
          ),
          categoryId: 'economy',
          categoryName: 'Movera',
          categoryImage: 'assets/images/rides/movera.webp',
          price: 459,
          paymentMethod: 'Cash',
        ),
      );
      await reservations.assignMockDriver(
        ride.reservationId,
        driver: const ReservationDriver(
          firstName: 'Amina',
          rating: 4.9,
          vehicle: 'Volvo EX40',
          plate: 'ABC 123',
        ),
      );
      await reservations.update(
        ride.reservationId,
        const ReservationPatch(status: ReservationStatus.driverEnRoute),
      );
    });
    expect(reservations.byId(ride.reservationId)!.revealsDriver, isTrue);

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) =>
            MaterialApp(navigatorKey: moveraNavigatorKey, home: const Home()),
      ),
    );

    var most = 0;
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      final now = mapsMounted();
      if (now > most) most = now;
    }
    expect(find.byType(WaitingForDriver, skipOffstage: false), findsOneWidget);
    expect(most, 1, reason: 'Home map and live-ride map mounted together');
    expect(mapsMounted(), 1);

    unawaited(reservations.cancel(ride.reservationId, reason: 'test'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(minutes: 5));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Home stays parked when the page above it is replaced, and '
      'resumes once it is back on top', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    FindingDriverController.active = null;
    AppScope.instance.ride
      ..rideId = null
      ..status = RideStatus.idle
      ..suppressRestore = false;

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) =>
            MaterialApp(navigatorKey: moveraNavigatorKey, home: const Home()),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final homeMap = find.byKey(const ValueKey('home-map'), skipOffstage: false);
    expect(homeMap, findsOneWidget);

    // A parked flow page (the menu here; SelectRide in Book for later) is
    // replaced by the next page, as RideScheduledPage replaces SelectRide.
    await tester.tap(find.byIcon(Icons.menu_open_rounded));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(homeMap, findsNothing);
    unawaited(
      moveraNavigatorKey.currentState!.pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Ride scheduled')),
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      expect(homeMap, findsNothing, reason: 'Home map remounted under a page');
    }
    expect(find.text('Ride scheduled'), findsOneWidget);

    moveraNavigatorKey.currentState!.pop();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(homeMap, findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('a page pushed over Home by another widget parks the map once '
      'it covers Home', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    FindingDriverController.active = null;
    AppScope.instance.ride
      ..rideId = null
      ..status = RideStatus.idle
      ..suppressRestore = false;

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) =>
            MaterialApp(navigatorKey: moveraNavigatorKey, home: const Home()),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final homeMap = find.byKey(const ValueKey('home-map'), skipOffstage: false);
    expect(homeMap, findsOneWidget);

    unawaited(
      moveraNavigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Support')),
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(homeMap, findsNothing);

    moveraNavigatorKey.currentState!.pop();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(homeMap, findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    debugDefaultTargetPlatformOverride = null;
  });
}
