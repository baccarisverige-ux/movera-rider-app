import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/navigator_key.dart';
import 'package:movera_rider/core/location/location_repository.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/presentation/finding_drivers.dart';
import 'package:movera_rider/features/destination_search/presentation/route_picker_page.dart';
import 'package:movera_rider/features/home/presentation/home.dart';
import 'package:movera_rider/features/pickup/presentation/confirm_pickup_spot.dart';
import 'package:movera_rider/features/pickup/presentation/set_pickup_page.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/shared/widgets/custom_google_map.dart';
import 'package:movera_rider/shared/widgets/parkable_map.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// G25 step A (supervisor NO-GO 2026-11-12, finding 2): on native a covered
/// ride-stage map stays mounted (no new platform view on the way back), so
/// the maps of the screens under the current one are all live at once. The
/// web-only count tests (NAV-3 audit_fix_map_parking, home_route_flow_map)
/// run in web mode; this one pins the native maximum through a real booking
/// until step B (one shared ride-stage map) lowers it:
/// at most [maxUnderWaiting] under Waiting (Home, Select ride, Finding,
/// Waiting) and [maxWithMovePickup] with the three dots' screen open over
/// Waiting. A real-phone memory check of these counts is still NOT CHECKED.
const int maxUnderWaiting = 4;
const int maxWithMovePickup = 5;

int _liveMaps() =>
    find.byType(CustomGoogleMap, skipOffstage: false).evaluate().length;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // Item 9: Home opens its map on a position this session knows (no GPS
    // answers in tests).
    LocationRepository.noteSessionFix(const GeoPoint(59.3293, 18.0686));
    CustomGoogleMap.debugMounted.clear();
    // Native rule (the default off the web), stated so a web default
    // cannot make this test pass by itself.
    ParkableMap.debugKeepWhileParked = true;
  });
  tearDown(() {
    ParkableMap.debugKeepWhileParked = null;
    LocationRepository.debugForgetSessionFix();
    CustomGoogleMap.debugMounted.clear();
  });

  testWidgets('native: a booking to Waiting keeps at most $maxUnderWaiting '
      'live maps, $maxWithMovePickup with the three dots open', (tester) async {
    var most = 0;
    Future<void> pump([Duration? d]) async {
      await tester.pump(d);
      final now = _liveMaps();
      if (now > most) most = now;
    }

    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // flutter_test defaults defaultTargetPlatform to android, which makes
    // SecureTokenStore route the geocode/booking calls this journey makes
    // through the live flutter_secure_storage platform channel. With no
    // native host to answer it, that channel call never completes, hanging
    // every authenticated request made from inside the pumped widget tree.
    // Force a desktop platform so SecureTokenStore falls back to its
    // in-memory store, matching how the app actually behaves on web/Linux.
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    FindingDriverController.active = null;
    AppScope.instance.ride
      ..rideId = null
      ..status = RideStatus.idle
      ..suppressRestore = false
      ..authoritativeVersion = null
      ..authoritativeUpdatedAt = null;

    final realtime = AppScope.instance.rideRealtime;
    expect(realtime, isA<MockRideRealtime>());

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        minTextAdapt: true,
        splitScreenMode: true,
        builder: (_, __) =>
            MaterialApp(navigatorKey: moveraNavigatorKey, home: const Home()),
      ),
    );
    // Real frames, so Home can settle (the promotion ticket may seat the
    // sheet a few frames after launch).
    for (var i = 0; i < 8; i++) {
      await pump(const Duration(milliseconds: 100));
    }

    expect(find.byType(Home), findsOneWidget);
    expect(find.text('Where to?'), findsOneWidget);

    await tester.tap(find.text('Where to?'));
    for (
      var i = 0;
      i < 40 && find.byType(TextField).evaluate().length < 2;
      i++
    ) {
      await pump(const Duration(milliseconds: 100));
    }

    final routeFields = find.byType(TextField);
    expect(routeFields, findsAtLeastNWidgets(2));

    // The sheet fields exist before the smooth-sheet route has fully reached
    // its resting position. Wait past the production 380 ms open motion so
    // the test taps the same settled geometry a Rider sees.
    await pump(const Duration(milliseconds: 450));

    await tester.enterText(routeFields.at(0), 'Stockholm Central');
    await pump();
    await tester.enterText(routeFields.at(1), 'Arlanda Airport');
    await pump();

    // No Next button: tapping a real suggested address moves on.
    final suggestion = find.text('Airport Terminal 5', findRichText: true);
    var arlanda = find.textContaining('Arlanda Airport', findRichText: true);
    for (var i = 0; i < 30 && arlanda.evaluate().length < 2; i++) {
      await pump(const Duration(milliseconds: 100));
      arlanda = find.textContaining('Arlanda Airport', findRichText: true);
    }
    expect(find.text('Next'), findsNothing);
    expect(suggestion, findsNothing);
    final pick = find.textContaining(
      'Stockholm Arlanda Airport',
      findRichText: true,
    );
    expect(pick, findsWidgets);
    await tester.tap(pick.first);
    // The route sheet closes, both addresses are normalized in parallel, and
    // the production category selector is pushed.
    for (var i = 0; i < 30 && find.byType(SelectRide).evaluate().isEmpty; i++) {
      await pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(SelectRide), findsOneWidget);
    // The rider looks at the categories: Select ride's own map is shown
    // (a phone mounts it once the route settles) before they book.
    final selectRideMap = find.byKey(const ValueKey('select-ride-map'));
    for (var i = 0; i < 40 && selectRideMap.evaluate().isEmpty; i++) {
      await pump(const Duration(milliseconds: 100));
    }
    expect(selectRideMap, findsOneWidget);

    // Quotes are backend-authored even in demo/test composition. Wait for
    // the category CTA to become actionable instead of bypassing selection.
    Finder selectMovera = find.text('Select Movera');
    for (var i = 0; i < 40 && selectMovera.evaluate().isEmpty; i++) {
      await pump(const Duration(milliseconds: 100));
      selectMovera = find.text('Select Movera');
    }
    expect(selectMovera, findsOneWidget);
    await tester.ensureVisible(selectMovera);
    await tester.tap(selectMovera);

    // Set pickup opens after Book, with the pickup preselected.
    for (
      var i = 0;
      i < 40 && find.byType(SetPickupPage).evaluate().isEmpty;
      i++
    ) {
      await pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(SetPickupPage), findsOneWidget);
    final confirmSearch = find.text('Confirm and search');
    expect(confirmSearch, findsOneWidget);
    // P5-R6: Set pickup finishes opening before the rider confirms (a tap
    // while it slides in is the second tap of a double tap and is ignored).
    await pump(const Duration(milliseconds: 300));
    await tester.tap(confirmSearch);

    for (
      var i = 0;
      i < 40 && find.byType(FindingDrivers).evaluate().isEmpty;
      i++
    ) {
      await pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(FindingDrivers), findsOneWidget);
    expect(AppScope.instance.ride.status, RideStatus.findingDriver);
    final rideId = AppScope.instance.ride.rideId;
    expect(rideId, isNotNull);
    expect(rideId!.trim(), isNotEmpty);

    final mock = realtime as MockRideRealtime;
    mock.assignNow();
    for (
      var i = 0;
      i < 50 && find.byType(WaitingForDriver).evaluate().isEmpty;
      i++
    ) {
      await pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(WaitingForDriver), findsOneWidget);
    expect(AppScope.instance.ride.rideId, rideId);
    expect(AppScope.instance.ride.status.isMatched, isTrue);

    // ignore: avoid_print
    print(
      'G25 native live maps, most up to Waiting: $most, now ${_liveMaps()}',
    );
    expect(
      most,
      lessThanOrEqualTo(maxUnderWaiting),
      reason: 'more live native maps than G25 step A allows under Waiting',
    );
    expect(
      _liveMaps(),
      maxUnderWaiting,
      reason: 'Home, Select ride, Finding and Waiting stay mounted',
    );

    // The three dots on the ride card (demo wire: the route screen), then
    // its map: a screen with its own map over Waiting (as Move pickup).
    final dots = find.byIcon(Icons.more_horiz_rounded);
    expect(dots, findsWidgets);
    await tester.ensureVisible(dots.last);
    await tester.tap(dots.last);
    final picker = find.byType(RoutePickerPage);
    for (var i = 0; i < 40 && picker.evaluate().isEmpty; i++) {
      await pump(const Duration(milliseconds: 100));
    }
    expect(picker, findsOneWidget);
    await pump(const Duration(milliseconds: 500));
    final onMap = find.bySemanticsLabel(
      RegExp('^(Choose destination on map|Set pickup on map)\$'),
    );
    expect(onMap, findsWidgets);
    await tester.tap(onMap.first);
    final spot = find.byType(ConfirmPickupSpot);
    for (var i = 0; i < 40 && spot.evaluate().isEmpty; i++) {
      await pump(const Duration(milliseconds: 100));
    }
    expect(spot, findsOneWidget);
    for (var i = 0; i < 10; i++) {
      await pump(const Duration(milliseconds: 100));
    }
    // ignore: avoid_print
    print(
      'G25 native live maps with a map screen over Waiting: ${_liveMaps()}, '
      'most $most',
    );
    expect(
      _liveMaps(),
      maxWithMovePickup,
      reason: 'Home, Select ride, Finding, Waiting and the screen on top',
    );
    expect(
      most,
      lessThanOrEqualTo(maxWithMovePickup),
      reason: 'more live native maps than G25 step A allows',
    );

    mock.unsubscribe();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(minutes: 5));
    debugDefaultTargetPlatformOverride = null;
  });
}
