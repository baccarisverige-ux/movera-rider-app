import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/navigator_key.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/maps/map_owners.dart';
import 'package:movera_rider/shared/widgets/custom_google_map.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/home/presentation/home.dart';
import 'package:movera_rider/features/home/presentation/side_menu.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Location allowed. The first [failFirst] one-shot fixes fail (a cold GPS
/// that times out); later ones answer at [lat]/[lng]. The live stream is
/// driven by hand.
class _SlowGeolocator extends GeolocatorPlatform {
  int failFirst = 1;

  /// While set, one-shot fixes wait for it (a slow first fix).
  Completer<void>? gate;
  double lat = 59.3293;
  double lng = 18.0686;
  int currentPositionCalls = 0;
  final StreamController<Position> live = StreamController.broadcast();

  DateTime clock = DateTime(2026, 10, 1, 12);

  void moveTo(double newLat, double newLng) {
    lat = newLat;
    lng = newLng;
    clock = clock.add(const Duration(seconds: 1));
    live.add(position);
  }

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
    if (currentPositionCalls <= failFirst) {
      throw TimeoutException('cold fix');
    }
    final wait = gate;
    if (wait != null) await wait.future;
    return position;
  }

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) =>
      live.stream;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  late GeolocatorPlatform original;
  late _SlowGeolocator gps;

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
    gps = _SlowGeolocator();
    GeolocatorPlatform.instance = gps;
  });
  tearDown(() {
    GeolocatorPlatform.instance = original;
    gps.live.close();
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
  Future<bool> liveTrackingStarted(WidgetTester tester) async {
    for (var i = 0; i < 5 && !gps.live.hasListener; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await frames(tester, 2);
    }
    return gps.live.hasListener;
  }

  Future<void> tearDownHome(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 40));
    debugDefaultTargetPlatformOverride = null;
  }

  testWidgets('rider-u119: a first fix that times out is tried again and '
      'live tracking starts while the rider stays on Home', (tester) async {
    await pumpHome(tester);
    expect(gps.currentPositionCalls, 1);
    expect(gps.live.hasListener, isFalse);
    // The rider stays on Home; nothing is backgrounded or booked.
    await frames(tester, 40);
    expect(gps.currentPositionCalls, greaterThan(1));
    expect(await liveTrackingStarted(tester), isTrue);
    await tearDownHome(tester);
  });

  bool puckPainted(WidgetTester tester) =>
      (tester.widget<CustomGoogleMap>(find.byType(CustomGoogleMap)).markers ??
              const <Marker>{})
          .any(
            (marker) => marker.markerId == const MarkerId('live_user_location'),
          );

  testWidgets('rider-u118: an app resume after a failed first fix draws the '
      'puck when fixes come in', (tester) async {
    await pumpHome(tester);
    expect(gps.live.hasListener, isFalse);
    // The rider switches away and back before Home tries again.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await frames(tester, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await frames(tester, 1);
    expect(await liveTrackingStarted(tester), isTrue);
    gps.moveTo(59.3300, 18.0690);
    await frames(tester, 30);
    expect(puckPainted(tester), isTrue);
    expect(find.text('Location off, set pickup'), findsNothing);
    await tearDownHome(tester);
  });

  testWidgets('rider-44: a late first fix does not move the map of the '
      'screen on top of Home', (tester) async {
    gps
      ..failFirst = 0
      ..gate = Completer<void>();
    final maps = AppScope.instance.maps;
    final commands = <String?>[];
    maps.debugOnCameraCommand = (owner, GeoPoint target) {
      if (target.latitude == gps.lat) commands.add(owner);
    };
    addTearDown(() {
      maps.debugOnCameraCommand = null;
      maps.detach(owner: MapOwners.pickup);
    });
    await pumpHome(tester);
    // The rider moves on before the fix lands: Home parks under a page and
    // that page's map takes the camera.
    await tester.tap(find.byIcon(Icons.menu_open_rounded));
    await frames(tester, 10);
    expect(find.byType(RiderMenuPage), findsOneWidget);
    maps.debugAttach(MapOwners.pickup);
    gps.gate!.complete();
    gps.gate = null;
    await liveTrackingStarted(tester);
    await frames(tester, 10);
    expect(commands, isNot(contains(MapOwners.pickup)));
    await tearDownHome(tester);
  });
}
