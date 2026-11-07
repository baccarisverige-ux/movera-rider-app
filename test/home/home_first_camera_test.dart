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
import 'package:movera_rider/core/location/location_repository.dart';
import 'package:movera_rider/shared/widgets/custom_google_map.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/home/presentation/home.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Owner decision "Home map start" (2026-11-07, like the driver app): Home's
/// map opens at once on the last known position, never on central
/// Stockholm with a flight to the rider. First time with no known position:
/// a "locating" surface (at most [homeStartWaitLimit]) and then the map at
/// the first fix, else at the zone default without a flight.
///
/// PROOF (problem 1): Home's map was born at central Stockholm
/// even when the app already knows where the rider was (saved last good
/// fix, Upplands Väsby). Location allowed. The first [failFirst] one-shot fixes fail (a cold GPS
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
    // Owner round 1: Home's quick coarse fix. A cold GPS has none either;
    // only the accurate one-shot fixes are counted here.
    if (locationSettings?.accuracy == LocationAccuracy.low) {
      throw TimeoutException('no quick fix');
    }
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
    LocationRepository.debugForgetSessionFix();
    SharedPreferences.setMockInitialValues(<String, Object>{
      'movera.location.last_good_fix.v1':
          '{"lat":59.5180,"lng":17.9110,"savedAt":"2026-11-06T10:00:00Z"}',
    });
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

  testWidgets('problem 1: Home map opens on the saved last fix, not on '
      'central Stockholm', (tester) async {
    gps
      ..failFirst = 0
      ..gate = Completer<void>(); // the accurate GPS fix is still coming
    await pumpHome(tester);
    final map = tester.widget<CustomGoogleMap>(find.byType(CustomGoogleMap));
    final start = map.initialPosition!.target;
    // ignore: avoid_print
    print('PROOF initial camera: ${start.latitude},${start.longitude}');
    expect(
      start.latitude,
      closeTo(59.5180, 0.001),
      reason: 'first camera is the default city, not the rider',
    );
    expect(start.longitude, closeTo(17.9110, 0.001));
    gps.gate!.complete();
    gps.gate = null;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 40));
    debugDefaultTargetPlatformOverride = null;
  });

  LatLng? mapStart(WidgetTester tester) {
    final maps = find.byType(CustomGoogleMap);
    if (maps.evaluate().isEmpty) return null;
    return tester.widget<CustomGoogleMap>(maps).initialPosition!.target;
  }

  Future<void> leave(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 40));
    debugDefaultTargetPlatformOverride = null;
  }

  testWidgets('C5: back on Home (a new Home after a trip) the map is born '
      'on the position this session already knows', (tester) async {
    gps
      ..failFirst = 0
      ..lat = 59.6000
      ..lng = 17.8500;
    await pumpHome(tester);
    await frames(tester, 20); // the accurate fix lands and is saved
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    // The rider comes back to Home: a new Home is built.
    gps.gate = Completer<void>();
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) =>
            MaterialApp(navigatorKey: moveraNavigatorKey, home: const Home()),
      ),
    );
    await tester.pump();
    final start = mapStart(tester);
    // ignore: avoid_print
    print('C5 first camera of the new Home: $start');
    expect(start, isNotNull, reason: 'the map is there on the first frame');
    expect(
      start!.latitude,
      closeTo(59.6000, 0.001),
      reason: 'a rebuilt Home started at central Stockholm',
    );
    expect(start.longitude, closeTo(17.8500, 0.001));
    gps.gate!.complete();
    gps.gate = null;
    await leave(tester);
  });

  testWidgets('first time, nothing known: "locating" first, then the map is '
      'born on the first fix (no Stockholm)', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    gps
      ..failFirst = 0
      ..lat = 59.6100
      ..lng = 17.8400
      ..gate = Completer<void>();
    await pumpHome(tester); // 0.8 s
    // ignore: avoid_print
    print('first time, before the fix: map=${mapStart(tester)}');
    expect(
      mapStart(tester),
      isNull,
      reason: 'no map at a made-up place while the first fix comes',
    );
    expect(find.byKey(const ValueKey('home-map-locating')), findsOneWidget);
    gps.gate!.complete();
    gps.gate = null;
    await frames(tester, 5);
    final start = mapStart(tester);
    // ignore: avoid_print
    print('first time, map born at: $start');
    expect(start, isNotNull);
    expect(start!.latitude, closeTo(59.6100, 0.001));
    expect(find.byKey(const ValueKey('home-map-locating')), findsNothing);
    await leave(tester);
  });

  testWidgets('first time, no fix within the wait: the map opens at the zone '
      'default (no flight)', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    gps
      ..failFirst = 0
      ..gate = Completer<void>(); // the GPS never answers in time
    await pumpHome(tester); // 0.8 s
    expect(find.byKey(const ValueKey('home-map-locating')), findsOneWidget);
    await frames(tester, 25); // past the 3 s wait
    final start = mapStart(tester);
    // ignore: avoid_print
    print('first time, no fix: map born at $start');
    expect(start, isNotNull, reason: 'the map is not held back for good');
    expect(start!.latitude, closeTo(59.3293, 0.001));
    expect(find.byKey(const ValueKey('home-map-locating')), findsNothing);
    gps.gate!.complete();
    gps.gate = null;
    await leave(tester);
  });
}
