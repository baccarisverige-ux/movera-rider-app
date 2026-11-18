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
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A phone with a precise location fix.
class _Geo extends GeolocatorPlatform {
  @override
  Future<bool> isLocationServiceEnabled() async => true;
  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.whileInUse;
  @override
  Future<LocationPermission> requestPermission() async =>
      LocationPermission.whileInUse;
  @override
  Future<LocationAccuracyStatus> getLocationAccuracy() async =>
      LocationAccuracyStatus.precise;
  @override
  Future<Position?> getLastKnownPosition({
    bool forceLocationManager = false,
  }) async => null;
  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async => Position(
    latitude: 59.33,
    longitude: 18.06,
    timestamp: DateTime.utc(2026, 11, 18),
    accuracy: 5,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) =>
      StreamController<Position>().stream;
}

/// Owner 2026-11-18: on a fresh app start, Home's places pop-up → a recent
/// address → the FIRST categories opening shows the S3 save sheet right
/// after the two-part open animation (no 2 s wait).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  late GeolocatorPlatform previous;
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'movera_recent_addresses': <String>['Stockholm Arlanda Airport'],
    });
    previous = GeolocatorPlatform.instance;
    GeolocatorPlatform.instance = _Geo();
    FindingDriverController.active = null;
    AppScope.instance.ride
      ..rideId = null
      ..status = RideStatus.idle
      ..suppressRestore = false
      ..authoritativeVersion = null
      ..authoritativeUpdatedAt = null;
  });
  tearDown(() => GeolocatorPlatform.instance = previous);

  const screen = Size(390, 844);

  /// Fresh start → places pop-up → the recent address → the categories.
  Future<void> openFromRecent(WidgetTester tester) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: screen,
        builder: (_, __) =>
            MaterialApp(navigatorKey: moveraNavigatorKey, home: const Home()),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.byKey(const ValueKey('home-places')));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.byKey(const ValueKey('places-popup-recent-0')));
    final categories = find.byType(SelectRide, skipOffstage: false);
    for (var i = 0; i < 2000 && categories.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 4));
    }
    expect(categories, findsOneWidget);
  }

  Future<void> tearDownApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 10));
    debugDefaultTargetPlatformOverride = null;
  }

  testWidgets('fresh start: recent → first categories open shows S3', (
    tester,
  ) async {
    await openFromRecent(tester);
    // The two-part open (~300 ms) and the sheet's slide (~320 ms): well
    // under a second, not ~2 s later.
    for (var i = 0; i < 9; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Save this address?'), findsOneWidget);
    await tearDownApp(tester);
  });

  testWidgets('a long first frame (the web map loading) does not use up '
      'the 5 s before the sheet was ever seen', (tester) async {
    await openFromRecent(tester);
    // Right as the screen starts to open, 8 s pass with no frame drawn
    // (the first opening's map load on the web).
    await tester.binding.delayed(const Duration(seconds: 8));
    for (var i = 0; i < 9; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Save this address?'), findsOneWidget);
    // Then the usual 5 s with no action closes it.
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Save this address?'), findsNothing);
    await tearDownApp(tester);
  });
}
