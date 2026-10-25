import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/navigator_key.dart';
import 'package:movera_rider/features/destination_search/presentation/route_picker_page.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/home/presentation/home.dart';
import 'package:movera_rider/features/home/presentation/side_menu.dart';
import 'package:movera_rider/features/home/presentation/widgets/where_to_card.dart';
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

  Future<void> frames(WidgetTester tester, int count, {int ms = 100}) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(Duration(milliseconds: ms));
    }
  }

  Future<void> pumpHome(WidgetTester tester) async {
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
  }

  /// Live tracking starts once the puck icons decode, on a real clock.
  Future<void> waitForLiveTracking(
    WidgetTester tester,
    _FakeGeolocator gps,
  ) async {
    for (var i = 0; i < 5 && !gps.live.hasListener; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await frames(tester, 2);
    }
    expect(gps.live.hasListener, isTrue);
  }

  Future<void> tearDownHome(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 10));
    debugDefaultTargetPlatformOverride = null;
  }

  /// Home's own PopScope: it blocks the pop while the destination sheet is
  /// open, so canPop == false means the sheet is open.
  bool homeSheetOpen(WidgetTester tester) => !tester
      .widget<PopScope>(
        find
            .descendant(
              of: find.byType(Home, skipOffstage: false),
              matching: find.byWidgetPredicate(
                (widget) => widget is PopScope,
                skipOffstage: false,
              ),
            )
            .first,
      )
      .canPop;

  testWidgets('RIDE-9: two quick taps on Where to push one route picker', (
    tester,
  ) async {
    await pumpHome(tester);
    await tester.tap(find.text('Where to?'));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(find.text('Where to?'), warnIfMissed: false);
    await frames(tester, 20);
    expect(find.byType(RoutePickerPage, skipOffstage: false), findsOneWidget);
    await tearDownHome(tester);
  });

  testWidgets('NAV-6: menu Where to opens the sheet and keeps it open', (
    tester,
  ) async {
    await pumpHome(tester);
    await tester.tap(find.byIcon(Icons.menu_open_rounded));
    await frames(tester, 10);
    expect(find.byType(RiderMenuPage), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(RiderMenuPage),
        matching: find.text('Where to?'),
      ),
    );
    // The sheet opens with the tap and is never closed again by the menu's
    // cleanup (which reversed its animation before the picker came up).
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      expect(homeSheetOpen(tester), isTrue, reason: 'sheet closed at frame $i');
    }
    expect(find.byType(RiderMenuPage), findsNothing);
    expect(find.byType(RoutePickerPage), findsOneWidget);
    expect(homeSheetOpen(tester), isTrue);
    await tearDownHome(tester);
  });

  testWidgets('RIDE-20: closing the address sheet before the search '
      'debounce fires throws nothing', (tester) async {
    await pumpHome(tester);
    // Raise the Home sheet so the saved places row is on screen.
    await tester.drag(find.byType(WhereToCard), const Offset(0, -400));
    await frames(tester, 10);
    await tester.tap(find.text('Set Work'));
    await frames(tester, 6);
    final field = find.byType(TextField).last;
    await tester.enterText(field, 'Kungs');
    await tester.pump(const Duration(milliseconds: 20));
    // Close right after typing.
    await tester.tap(find.byTooltip('Close').last);
    // Small frames, so the sheet unmounts (~280 ms) before the debounce
    // timer (320 ms after the last keystroke) fires.
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.text('Set Work address', skipOffstage: false), findsNothing);
    expect(tester.takeException(), isNull);
    await tearDownHome(tester);
  });

  group('with a location fix', () {
    late GeolocatorPlatform original;
    late _FakeGeolocator gps;

    setUp(() {
      original = GeolocatorPlatform.instance;
      gps = _FakeGeolocator(59.3293, 18.0686);
      GeolocatorPlatform.instance = gps;
    });
    tearDown(() {
      GeolocatorPlatform.instance = original;
      gps.live.close();
    });

    testWidgets('RIDE-9/RIDE-18: a double tap on a saved place opens one '
        'ride selection and shows no false "invalid address" error', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'movera_work_address': 'Arlanda Airport',
      });
      await pumpHome(tester);
      await waitForLiveTracking(tester, gps);
      await tester.drag(find.byType(WhereToCard), const Offset(0, -400));
      await frames(tester, 10);
      final work = find.text('Work');
      expect(work, findsWidgets);
      await tester.tap(work.first);
      await tester.tap(work.first, warnIfMissed: false);
      final error = find.text(
        'Choose a valid destination address.',
        skipOffstage: false,
      );
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        expect(error, findsNothing);
      }
      expect(find.byType(SelectRide, skipOffstage: false), findsOneWidget);
      await tearDownHome(tester);
    });

    testWidgets('RIDE-14: app resume leaves a parked Home paused', (
      tester,
    ) async {
      await pumpHome(tester);
      await waitForLiveTracking(tester, gps);
      await frames(tester, 10);
      // Park Home under a full-screen page.
      await tester.tap(find.byIcon(Icons.menu_open_rounded));
      await frames(tester, 10);
      expect(find.byType(RiderMenuPage), findsOneWidget);
      final before = gps.currentPositionCalls;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await frames(tester, 2);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await frames(tester, 10);
      expect(
        gps.currentPositionCalls,
        before,
        reason: 'a parked Home must not restart its live location on resume',
      );
      await tearDownHome(tester);
    });

    testWidgets('RIDE-10: a new booking starts from a fresh pickup label, '
        'not the last flow\'s street', (tester) async {
      await pumpHome(tester);
      await waitForLiveTracking(tester, gps);

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
      for (
        var i = 0;
        i < 30 && find.byType(SelectRide).evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(SelectRide), findsOneWidget);
      final usedPickup = tester
          .widget<SelectRide>(find.byType(SelectRide))
          .pickupAddress;
      expect(usedPickup, contains('Stockholm Central'));

      // The rider backs out to Home (owner round 1: through the address
      // screen, which Back reopens), then walks on with the app open.
      moveraNavigatorKey.currentState!.pop();
      await frames(tester, 15);
      expect(find.byType(SelectRide), findsNothing);
      expect(find.byType(RoutePickerPage), findsOneWidget);
      moveraNavigatorKey.currentState!.pop();
      await frames(tester, 15);
      expect(find.byType(RoutePickerPage), findsNothing);
      // About 130 m north, a fix a second.
      for (var i = 1; i <= 10; i++) {
        gps.moveTo(59.3293 + i * 0.00012, 18.0686);
        await tester.pump(const Duration(seconds: 1));
      }

      // The card now shows the last destination instead of "Where to?".
      await tester.tap(
        find.descendant(
          of: find.byType(WhereToCard),
          matching: find.byIcon(Icons.search_rounded),
        ),
      );
      await frames(tester, 20);
      final picker = tester.widget<RoutePickerPage>(
        find.byType(RoutePickerPage),
      );
      expect(picker.pickupAddress, isNot(usedPickup));
      expect(picker.here?.latitude, greaterThan(59.3293 + 0.0007));
      await tearDownHome(tester);
    });
  });
}
