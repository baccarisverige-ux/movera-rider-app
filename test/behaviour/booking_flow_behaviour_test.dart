import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/navigator_key.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/presentation/finding_drivers.dart';
import 'package:movera_rider/features/home/presentation/home.dart';
import 'package:movera_rider/features/pickup/presentation/confirm_pickup_spot.dart';
import 'package:movera_rider/features/pickup/presentation/set_pickup_page.dart';
import 'package:movera_rider/features/reservations/presentation/review_changes.dart';
import 'package:movera_rider/features/reservations/presentation/ride_scheduled.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';
import 'package:movera_rider/features/scheduled_rides/presentation/schedule_ride.dart';
import 'package:movera_rider/features/scheduled_rides/presentation/select_date_time.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// B16 (2026-11-04): Book now and Book for later, driven through the real
/// Home on the in-process demo transport. These replace source-reading
/// guards about which screens each mode may open (archived in
/// Rules/archive/old-tests/movera-rider-app/).

/// Pumps until [finder] shows, failing at once if [never] ever shows.
Future<void> _waitFor(
  WidgetTester tester,
  Finder finder, {
  Finder? never,
  int tries = 60,
}) async {
  for (var i = 0; i < tries && finder.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (never != null) expect(never, findsNothing);
  }
  expect(finder, findsWidgets);
}

Future<void> _pumpHome(WidgetTester tester) async {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(390, 844),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (_, __) =>
          MaterialApp(navigatorKey: moveraNavigatorKey, home: const Home()),
    ),
  );
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(find.byType(Home), findsOneWidget);
}

/// Where to: type both ends and pick Arlanda.
Future<void> _route(WidgetTester tester, {Finder? never}) async {
  for (var i = 0; i < 40 && find.byType(TextField).evaluate().length < 2; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump(const Duration(milliseconds: 450));
  await tester.enterText(find.byType(TextField).at(0), 'Stockholm Central');
  await tester.pump();
  await tester.enterText(find.byType(TextField).at(1), 'Arlanda');
  await tester.pump();
  final pick = find.textContaining(
    'Stockholm Arlanda Airport',
    findRichText: true,
  );
  await _waitFor(tester, pick, never: never);
  await tester.tap(pick.first);
}

Future<void> _end(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 6));
  debugDefaultTargetPlatformOverride = null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FindingDriverController.active = null;
    AppScope.instance.ride
      ..rideId = null
      ..status = RideStatus.idle
      ..suppressRestore = false
      ..authoritativeVersion = null
      ..authoritativeUpdatedAt = null;
  });

  testWidgets('Book now: Set pickup always opens after Book and before the '
      'search; a double tap opens it once', (tester) async {
    await _pumpHome(tester);
    final reservationsBefore = AppScope.instance.reservations.all.length;
    await tester.tap(find.text('Where to?'));
    await _route(tester);
    await _waitFor(tester, find.byType(SelectRide));
    final select = find.text('Select Movera');
    await _waitFor(tester, select);
    await tester.ensureVisible(select);
    // Double tap: the CTA locks after the first.
    await tester.tap(select);
    await tester.tap(select, warnIfMissed: false);
    await _waitFor(
      tester,
      find.byType(SetPickupPage),
      never: find.byType(FindingDrivers),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(SetPickupPage), findsOneWidget);
    expect(find.text('Confirm and search'), findsOneWidget);
    expect(find.byType(FindingDrivers), findsNothing);
    expect(AppScope.instance.ride.status, RideStatus.idle);

    await tester.tap(find.text('Confirm and search'));
    await _waitFor(tester, find.byType(FindingDrivers));
    expect(find.byType(FindingDrivers), findsOneWidget);
    expect(AppScope.instance.ride.status, RideStatus.findingDriver);
    expect(FindingDriverController.active, isNotNull);
    expect(find.text('Anything we should know?'), findsNothing);
    // An on-demand search is never turned into a reservation.
    expect(AppScope.instance.reservations.all, hasLength(reservationsBefore));
    await _end(tester);
  });

  testWidgets('Book for later never enters Finding Driver and ends on "Your '
      'ride is scheduled"', (tester) async {
    final finding = find.byType(FindingDrivers);
    await _pumpHome(tester);
    await tester.tap(find.text('Later'));
    // Later uses the same Where to as Book now, not the old Plan your ride
    // screen (that one is for History and editing).
    await _route(
      tester,
      never: find.byWidgetPredicate(
        (w) => w is FindingDrivers || w is ScheduleRide,
      ),
    );
    await _waitFor(
      tester,
      find.byType(ScheduleDateTimeSelector),
      never: finding,
    );
    await tester.tap(find.text('Continue'));
    await _waitFor(tester, find.byType(SelectRide), never: finding);
    final schedule = find.text('Schedule Movera');
    await _waitFor(tester, schedule, never: finding);
    expect(find.text('Select Movera'), findsNothing);
    expect(find.text('Anything we should know?'), findsNothing);
    await tester.ensureVisible(schedule);
    await tester.tap(schedule);
    await _waitFor(tester, find.byType(SetPickupPage), never: finding);
    expect(find.text('Confirm and schedule'), findsOneWidget);
    final reservationsBefore = AppScope.instance.reservations.all.length;
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Confirm and schedule'));
    // The pickup was just set: checkout books straight away, with no
    // second pickup confirmation or review page.
    final afterPickup = find.byWidgetPredicate(
      (w) =>
          w is FindingDrivers ||
          w is ConfirmPickupSpot ||
          w is ReviewChangesPage,
    );
    await _waitFor(tester, find.byType(RideScheduledPage), never: afterPickup);
    expect(
      AppScope.instance.reservations.all,
      hasLength(reservationsBefore + 1),
    );
    expect(AppScope.instance.ride.status, RideStatus.idle);
    expect(FindingDriverController.active, isNull);
    await tester.pump(const Duration(seconds: 6));
    expect(finding, findsNothing);
    await _end(tester);
  });
}
