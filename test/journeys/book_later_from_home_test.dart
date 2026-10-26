import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/navigator_key.dart';
import 'package:movera_rider/features/home/presentation/home.dart';
import 'package:movera_rider/features/pickup/presentation/set_pickup_page.dart';
import 'package:movera_rider/features/reservations/presentation/ride_scheduled.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';
import 'package:movera_rider/features/scheduled_rides/presentation/select_date_time.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Book for later follows the Book now screens: Home "Later" → Where to →
/// date & time → categories (scheduled) → Set pickup ("Confirm and
/// schedule") → "Your ride is scheduled".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    AppScope.instance.ride
      ..rideId = null
      ..status = RideStatus.idle
      ..suppressRestore = false;
  });

  Future<void> waitFor(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 60 && finder.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(finder, findsWidgets);
  }

  testWidgets(
    'Home Later -> Where to -> date & time -> scheduled categories -> Set pickup -> scheduled',
    (tester) async {
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

      // "Later" opens the same Where to as Book now, not the old screen.
      await tester.tap(find.text('Later'));
      for (
        var i = 0;
        i < 40 && find.byType(TextField).evaluate().length < 2;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Plan your ride'), findsOneWidget);
      expect(find.text('Next'), findsNothing);
      await tester.pump(const Duration(milliseconds: 450));
      // The test Home has no GPS fix, so type the pickup as the journey
      // test does; a real phone prefills the current location.
      await tester.enterText(find.byType(TextField).at(0), 'Stockholm Central');
      await tester.pump();
      await tester.enterText(find.byType(TextField).at(1), 'Arlanda');
      await tester.pump();
      final pick = find.textContaining(
        'Stockholm Arlanda Airport',
        findRichText: true,
      );
      await waitFor(tester, pick);
      await tester.tap(pick.first);

      // Date & time, with an arrival estimate from the real trip.
      await waitFor(tester, find.byType(ScheduleDateTimeSelector));
      expect(find.text('Estimated arrival'), findsOneWidget);
      await tester.tap(find.text('Continue'));

      // Categories in scheduled mode: pickup time in the rows, Schedule CTA.
      await waitFor(tester, find.byType(SelectRide));
      final schedule = find.text('Schedule Movera');
      await waitFor(tester, schedule);
      expect(find.textContaining('Pickup ', findRichText: true), findsWidgets);
      expect(find.textContaining(' min · Arrive'), findsNothing);
      await tester.ensureVisible(schedule);
      await tester.tap(schedule);

      // Set pickup, ending in "Confirm and schedule" (never a search).
      await waitFor(tester, find.byType(SetPickupPage));
      expect(find.text('Confirm and schedule'), findsOneWidget);
      expect(find.text('Confirm and search'), findsNothing);
      expect(find.textContaining('Pickup '), findsWidgets);
      await tester.tap(find.text('Confirm and schedule'));

      await waitFor(tester, find.byType(RideScheduledPage));
      expect(find.text('Your ride is scheduled'), findsOneWidget);
      expect(AppScope.instance.ride.status, RideStatus.idle);

      // Let the booked popup's timers run out before the test ends.
      await tester.pump(const Duration(seconds: 6));
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
