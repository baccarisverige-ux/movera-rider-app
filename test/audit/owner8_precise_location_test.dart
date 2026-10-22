import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/navigator_key.dart';
import 'package:movera_rider/core/location/app_geocoding.dart';
import 'package:movera_rider/core/location/location_access_issue.dart';
import 'package:movera_rider/core/location/location_repository.dart';
import 'package:movera_rider/core/motion/motion_engine.dart';
import 'package:movera_rider/features/destination_search/presentation/route_picker_page.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/home/application/home_controller.dart';
import 'package:movera_rider/features/home/presentation/home.dart';
import 'package:movera_rider/features/home/presentation/widgets/home_location_notice.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Owner decision 8 (rider-u114): an approximate-only grant shows the
/// 'Precise location is off' notice and never fills the pickup.
class _Geo extends GeolocatorPlatform {
  LocationAccuracyStatus accuracy = LocationAccuracyStatus.reduced;
  final List<String> calls = [];

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.whileInUse;

  @override
  Future<LocationPermission> requestPermission() async {
    calls.add('requestPermission');
    return LocationPermission.whileInUse;
  }

  @override
  Future<LocationAccuracyStatus> getLocationAccuracy() async => accuracy;

  @override
  Future<LocationAccuracyStatus> requestTemporaryFullAccuracy({
    required String purposeKey,
  }) async {
    calls.add('temporary:$purposeKey');
    return accuracy = LocationAccuracyStatus.precise;
  }

  @override
  Future<bool> openAppSettings() async {
    calls.add('openAppSettings');
    return true;
  }

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
    timestamp: DateTime.utc(2026, 10, 22),
    accuracy: accuracy == LocationAccuracyStatus.reduced ? 1500 : 5,
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

HomeLocationController _controller() => HomeLocationController(
  location: LocationRepository(isWeb: false),
  geocoding: AppGeocoding(),
  motion: MotionEngine(),
  startCompass: () async => false,
  readCompass: () => null,
  stopCompass: () {},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  late _Geo geo;
  late GeolocatorPlatform previous;
  setUp(() {
    previous = GeolocatorPlatform.instance;
    GeolocatorPlatform.instance = geo = _Geo();
  });
  tearDown(() {
    GeolocatorPlatform.instance = previous;
    debugDefaultTargetPlatformOverride = null;
  });

  test('approximate: no pickup from the fix; precise: the pickup', () async {
    final ctl = _controller();
    final approximate = await ctl.detectCurrent();
    expect(approximate.approximate, isTrue);
    expect(approximate.address, locationOffPickupLabel);
    expect(approximate.target, isNotNull, reason: 'the map may still centre');
    expect(ctl.accessIssue, LocationAccessIssue.approximate);

    geo.accuracy = LocationAccuracyStatus.precise;
    final precise = await ctl.detectCurrent();
    expect(precise.approximate, isFalse);
    expect(precise.address, isNot(locationOffPickupLabel));
    expect(ctl.accessIssue, isNull);
    ctl.dispose();
  });

  test('web never reports approximate location', () async {
    expect(await LocationRepository(isWeb: true).isApproximateOnly(), isFalse);
  });

  test('Turn on: iOS asks temporary full accuracy, Android fine', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(
      await LocationRepository(isWeb: false).requestPreciseLocation(),
      isTrue,
    );
    expect(geo.calls, ['temporary:${LocationRepository.precisePurposeKey}']);

    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    geo
      ..accuracy = LocationAccuracyStatus.reduced
      ..calls.clear();
    expect(
      await LocationRepository(isWeb: false).requestPreciseLocation(),
      isFalse,
    );
    expect(geo.calls, ['requestPermission', 'openAppSettings']);
  });

  testWidgets('the notice shows and its button asks for precise location', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final ctl = _controller();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              HomeLocationNotice(
                location: ctl,
                bottom: 100,
                onRetry: () {},
                onPrecise: ctl.requestPreciseLocation,
              ),
            ],
          ),
        ),
      ),
    );
    await ctl.detectCurrent();
    await tester.pump();
    expect(find.text('Precise location is off'), findsOneWidget);
    await tester.tap(find.text('Turn on'));
    await tester.pump();
    expect(geo.calls, ['temporary:PickupPrecision']);
    expect(find.text('Precise location is off'), findsNothing);
    ctl.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Home: set pickup while approximate; resume re-checks', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    Future<void> frames(int count) async {
      for (var i = 0; i < count; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    SharedPreferences.setMockInitialValues(<String, Object>{});
    FindingDriverController.active = null;
    AppScope.instance.ride
      ..rideId = null
      ..status = RideStatus.idle;

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) =>
            MaterialApp(navigatorKey: moveraNavigatorKey, home: const Home()),
      ),
    );
    await frames(8);
    expect(find.text('Precise location is off'), findsOneWidget);
    Future<RoutePickerPage> openWhereTo() async {
      await tester.tap(find.text('Where to?'));
      await frames(20);
      return tester.widget<RoutePickerPage>(
        find.byType(RoutePickerPage, skipOffstage: false),
      );
    }

    Future<void> closeWhereTo() async {
      moveraNavigatorKey.currentState!.pop();
      await frames(20);
    }

    var picker = await openWhereTo();
    expect(picker.pickupAddress, locationOffPickupLabel);
    expect(picker.here, isNull, reason: 'no pickup point from the fix');
    await closeWhereTo();

    // Precise turned on in Settings; the app comes back.
    geo.accuracy = LocationAccuracyStatus.precise;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await frames(8);
    expect(find.text('Precise location is off'), findsNothing);
    picker = await openWhereTo();
    expect(picker.here, isNotNull);
    expect(picker.pickupAddress, isNot(locationOffPickupLabel));
    await closeWhereTo();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 10));
    debugDefaultTargetPlatformOverride = null;
  });
}
