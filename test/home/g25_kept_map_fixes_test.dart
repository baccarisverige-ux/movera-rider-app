import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/navigator_key.dart';
import 'package:movera_rider/core/location/location_repository.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/home/presentation/home.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/shared/widgets/custom_google_map.dart';
import 'package:movera_rider/shared/widgets/parkable_map.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fixtures/fake_maps_platform.dart';

/// G25 step A, supervisor NO-GO 2026-11-12.
///
/// Finding 1: on native Home's map is kept under the trip screens, and a
/// trip ends with popUntil back to the same Home. The kept map used to come
/// back with the camera from before booking: a new map was born on the
/// rider (owner decision "Home map start"), a kept one was never moved.
///
/// Finding 3: a screen that parks before its map was ever shown (Select
/// ride parks before `_mapReady`) must not build a new map hidden: its
/// onMapCreated would take camera control from the covering screen.
class _Gps extends GeolocatorPlatform {
  double lat = 59.3293;
  double lng = 18.0686;
  DateTime clock = DateTime(2026, 11, 12, 12);
  final StreamController<Position> live = StreamController.broadcast();

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
    if (locationSettings?.accuracy == LocationAccuracy.low) {
      throw TimeoutException('no quick fix');
    }
    clock = clock.add(const Duration(seconds: 1));
    return position;
  }

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) =>
      live.stream;
}

/// The target of a camera command, when it names one.
List<double>? _targetOf(CameraUpdate update) {
  final json = update.toJson() as List<Object?>;
  if (json.first == 'newCameraPosition') {
    final target = (json[1]! as Map<Object?, Object?>)['target']!;
    return (target as List<Object?>).cast<double>();
  }
  if (json.first == 'newLatLng' || json.first == 'newLatLngZoom') {
    return (json[1]! as List<Object?>).cast<double>();
  }
  return null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  late FakeMapsPlatform fake;
  late GoogleMapsFlutterPlatform previousMaps;

  setUp(() {
    previousMaps = GoogleMapsFlutterPlatform.instance;
    fake = FakeMapsPlatform();
    GoogleMapsFlutterPlatform.instance = fake;
    CustomGoogleMap.debugWaitForMaps = false;
  });
  tearDown(() {
    CustomGoogleMap.debugWaitForMaps = null;
    ParkableMap.debugKeepWhileParked = null;
    GoogleMapsFlutterPlatform.instance = previousMaps;
  });

  group('finding 1: Home after a trip', () {
    late GeolocatorPlatform previousGps;
    late _Gps gps;

    setUp(() {
      LocationRepository.debugForgetSessionFix();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      FindingDriverController.active = null;
      AppScope.instance.ride
        ..rideId = null
        ..status = RideStatus.idle
        ..suppressRestore = false
        ..authoritativeVersion = null
        ..authoritativeUpdatedAt = null;
      previousGps = GeolocatorPlatform.instance;
      gps = _Gps();
      GeolocatorPlatform.instance = gps;
    });
    tearDown(() {
      GeolocatorPlatform.instance = previousGps;
      gps.live.close();
    });

    Future<void> frames(WidgetTester tester, int count) async {
      for (var i = 0; i < count; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    /// Home's first fix, then the rider's pin is drawn for real (an image)
    /// and the live location is bound.
    Future<void> settleHome(WidgetTester tester) async {
      await frames(tester, 20);
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('the kept map comes back on the rider, who moved 15 km '
        'during the trip', (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, __) =>
              MaterialApp(navigatorKey: moveraNavigatorKey, home: const Home()),
        ),
      );
      await settleHome(tester);
      expect(fake.createdIds, hasLength(1), reason: 'Home has its map');
      final homeMapId = fake.createdIds.single;

      // The trip: a page covers Home (popUntil brings the same Home back).
      unawaited(
        moveraNavigatorKey.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Trip')),
          ),
        ),
      );
      await frames(tester, 10);
      // The rider rides 15 km north while Home is covered (its GPS paused).
      gps
        ..lat = 59.3293 + 0.135
        ..lng = 18.0686;
      fake.cameraUpdates.clear();

      moveraNavigatorKey.currentState!.popUntil((route) => route.isFirst);
      await frames(tester, 20);

      expect(fake.createdIds, [homeMapId], reason: 'the same kept map');
      final homeMoves = fake.cameraUpdates
          .where((c) => c.mapId == homeMapId)
          .map((c) => _targetOf(c.update))
          .whereType<List<double>>()
          .toList();
      // ignore: avoid_print
      print('camera commands on the kept Home map after the trip: $homeMoves');
      expect(
        homeMoves,
        isNotEmpty,
        reason: 'the kept map kept the camera from before booking',
      );
      expect(homeMoves.last[0], closeTo(59.3293 + 0.135, 0.0005));
      expect(homeMoves.last[1], closeTo(18.0686, 0.0005));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 40));
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('a short cover where the rider did not move leaves the '
        'camera alone', (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, __) =>
              MaterialApp(navigatorKey: moveraNavigatorKey, home: const Home()),
        ),
      );
      await settleHome(tester);
      final homeMapId = fake.createdIds.single;
      unawaited(
        moveraNavigatorKey.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Menu')),
          ),
        ),
      );
      await frames(tester, 10);
      fake.cameraUpdates.clear();
      moveraNavigatorKey.currentState!.pop();
      await frames(tester, 20);
      expect(
        fake.cameraUpdates.where((c) => c.mapId == homeMapId),
        isEmpty,
        reason: 'no camera jump when the rider is where the map shows',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 40));
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('finding 3: ParkableMap never shown', () {
    Widget host(bool parked, {VoidCallback? onResumed}) => MaterialApp(
      home: ParkableMap(
        parked: parked,
        placeholder: const ColoredBox(
          key: ValueKey('placeholder'),
          color: Color(0xFFF6F5F1),
        ),
        onResumed: onResumed,
        child: const CustomGoogleMap(key: ValueKey('stage-map')),
      ),
    );

    testWidgets('a map parked before it was ever shown is not built hidden', (
      tester,
    ) async {
      var resumed = 0;
      // Select ride: parked (Book for later, the next stage) before
      // `_mapReady` mounted its map.
      await tester.pumpWidget(host(true, onResumed: () => resumed++));
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(const ValueKey('stage-map')),
        findsNothing,
        reason: 'a new map was built under the covering screen',
      );
      expect(fake.createdIds, isEmpty);
      expect(find.byKey(const ValueKey('placeholder')), findsOneWidget);

      // Shown: the first map is born now, and attaches itself (no resume).
      await tester.pumpWidget(host(false, onResumed: () => resumed++));
      await tester.pump();
      expect(fake.createdIds, hasLength(1));
      expect(resumed, 0);

      // Parked again after it was shown: kept (the G25 rule).
      await tester.pumpWidget(host(true, onResumed: () => resumed++));
      await tester.pump();
      expect(find.byKey(const ValueKey('stage-map')), findsOneWidget);
      await tester.pumpWidget(host(false, onResumed: () => resumed++));
      await tester.pump();
      expect(fake.createdIds, hasLength(1));
      expect(resumed, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
