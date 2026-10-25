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

  testWidgets('rider-u121: a saved place starts a new route without the '
      'stops of an earlier, abandoned one', (tester) async {
    final original = GeolocatorPlatform.instance;
    final gps = _FakeGeolocator(59.3293, 18.0686);
    GeolocatorPlatform.instance = gps;
    addTearDown(() {
      GeolocatorPlatform.instance = original;
      gps.live.close();
    });
    SharedPreferences.setMockInitialValues(<String, Object>{
      'movera_work_address': 'Arlanda Airport',
    });
    await pumpHome(tester);
    await waitForLiveTracking(tester, gps);

    // Where to: Stockholm Central -> stop Odenplan -> Arlanda.
    await tester.tap(find.text('Where to?'));
    for (
      var i = 0;
      i < 40 && find.byType(RoutePickerPage).evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await frames(tester, 5);
    moveraNavigatorKey.currentState!.pop(<String, dynamic>{
      'pickup': 'Stockholm Central',
      'pickupLat': 59.3300,
      'pickupLng': 18.0590,
      'pickupIsFallback': false,
      'destination': 'Arlanda Airport',
      'destinationLat': 59.6498,
      'destinationLng': 17.9238,
      'stops': <String>['Odenplan'],
    });
    for (var i = 0; i < 40 && find.byType(SelectRide).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.widget<SelectRide>(find.byType(SelectRide)).stops, [
      isNotEmpty,
    ]);

    // The rider looks at prices, backs out (owner round 1: Back lands on
    // the address screen first), closes it too, and later taps Work.
    moveraNavigatorKey.currentState!.pop();
    await frames(tester, 15);
    expect(find.byType(SelectRide), findsNothing);
    expect(find.byType(RoutePickerPage), findsOneWidget);
    moveraNavigatorKey.currentState!.pop();
    await frames(tester, 15);
    expect(find.byType(RoutePickerPage), findsNothing);
    await tester.drag(find.byType(WhereToCard), const Offset(0, -400));
    await frames(tester, 10);
    await tester.tap(find.text('Work').first);
    for (var i = 0; i < 60 && find.byType(SelectRide).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(SelectRide), findsOneWidget);
    expect(tester.widget<SelectRide>(find.byType(SelectRide)).stops, isEmpty);
    await tearDownHome(tester);
  });
}
