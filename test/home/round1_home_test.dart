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
import 'package:movera_rider/features/destination_search/presentation/route_picker_page.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/home/presentation/home.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';
import 'package:movera_rider/shared/widgets/custom_google_map.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Owner round 1 on Home: the fast first position, Back from the categories
/// screen to the address screen, and a map that keeps its size.
class _FakeGeolocator extends GeolocatorPlatform {
  _FakeGeolocator(this.lat, this.lng);

  double lat;
  double lng;

  /// The OS's cached position, if any.
  Position? lastKnown;

  /// While set, accurate one-shot fixes wait for it.
  Completer<void>? gate;
  final StreamController<Position> live = StreamController.broadcast();

  static Position at(double lat, double lng) => Position(
    latitude: lat,
    longitude: lng,
    timestamp: DateTime(2026, 10, 25, 12),
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
  }) async => lastKnown;

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    final wait = gate;
    if (wait != null) await wait.future;
    return at(lat, lng);
  }

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) =>
      live.stream;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  late GeolocatorPlatform original;
  late _FakeGeolocator gps;

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
    gps = _FakeGeolocator(59.3293, 18.0686);
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

  Future<void> tearDownHome(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 10));
    debugDefaultTargetPlatformOverride = null;
  }

  LatLng? puck(WidgetTester tester) {
    final markers =
        tester.widget<CustomGoogleMap>(find.byType(CustomGoogleMap)).markers ??
        const <Marker>{};
    for (final marker in markers) {
      if (marker.markerId == const MarkerId('live_user_location')) {
        return marker.position;
      }
    }
    return null;
  }

  /// The puck icons decode on a real clock.
  Future<void> waitFor(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 10 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await frames(tester, 2);
    }
  }

  group('fast first position', () {
    late List<GeoPoint> commands;

    setUp(() {
      commands = [];
      AppScope.instance.maps
        ..debugAttach(MapOwners.home)
        ..debugOnCameraCommand = (_, target) => commands.add(target);
    });
    tearDown(() {
      AppScope.instance.maps
        ..debugOnCameraCommand = null
        ..detach(owner: MapOwners.home);
    });

    testWidgets('the puck shows at the cached position while the accurate '
        'fix is still coming, then moves without a camera jump', (
      tester,
    ) async {
      // About 11 m apart.
      gps
        ..lastKnown = _FakeGeolocator.at(59.3292, 18.0686)
        ..gate = Completer<void>();
      await pumpHome(tester);
      await waitFor(tester, () => puck(tester) != null);
      expect(puck(tester), const LatLng(59.3292, 18.0686));
      expect(commands.map((p) => p.latitude), contains(59.3292));

      gps.gate!.complete();
      gps.gate = null;
      await waitFor(tester, () => gps.live.hasListener);
      await frames(tester, 10);
      expect(puck(tester), const LatLng(59.3293, 18.0686));
      expect(
        commands.map((p) => p.latitude),
        isNot(contains(59.3293)),
        reason: 'a refinement within 30 m leaves the camera where it is',
      );
      await tearDownHome(tester);
    });

    testWidgets('an accurate fix far from the quick one moves the camera', (
      tester,
    ) async {
      gps
        ..lastKnown = _FakeGeolocator.at(59.3200, 18.0686)
        ..gate = Completer<void>();
      await pumpHome(tester);
      await waitFor(tester, () => puck(tester) != null);
      expect(puck(tester), const LatLng(59.3200, 18.0686));
      gps.gate!.complete();
      gps.gate = null;
      await waitFor(tester, () => gps.live.hasListener);
      await frames(tester, 10);
      expect(commands.map((p) => p.latitude), contains(59.3293));
      await tearDownHome(tester);
    });
  });

  group('Back from the categories screen', () {
    Future<SelectRide> openCategories(WidgetTester tester) async {
      await pumpHome(tester);
      await waitFor(tester, () => gps.live.hasListener);
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
      for (
        var i = 0;
        i < 40 && find.byType(SelectRide).evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      return tester.widget<SelectRide>(find.byType(SelectRide));
    }

    testWidgets('reopens the address screen with the same route', (
      tester,
    ) async {
      final categories = await openCategories(tester);
      moveraNavigatorKey.currentState!.pop();
      await frames(tester, 15);
      expect(find.byType(SelectRide), findsNothing);
      final picker = tester.widget<RoutePickerPage>(
        find.byType(RoutePickerPage),
      );
      expect(picker.pickupAddress, categories.pickupAddress);
      expect(picker.destinationAddress, categories.destinationAddress);
      expect(picker.stops, categories.stops);
      expect(picker.here?.latitude, 59.3300, reason: 'the confirmed pickup');
      expect(picker.here?.longitude, 18.0590);

      // Closing the address screen lands on Home; nothing reopens again.
      moveraNavigatorKey.currentState!.pop();
      await frames(tester, 15);
      expect(find.byType(RoutePickerPage), findsNothing);
      expect(find.byType(SelectRide), findsNothing);
      expect(moveraNavigatorKey.currentState!.canPop(), isFalse);
      await tearDownHome(tester);
    });

    testWidgets('a booked ride never reopens the address screen', (
      tester,
    ) async {
      await openCategories(tester);
      // The flow left the categories screen with a ride.
      AppScope.instance.ride
        ..rideId = 'ride-round1'
        ..status = RideStatus.findingDriver;
      moveraNavigatorKey.currentState!.pop();
      await frames(tester, 15);
      expect(find.byType(SelectRide), findsNothing);
      expect(find.byType(RoutePickerPage), findsNothing);
      AppScope.instance.ride
        ..rideId = null
        ..status = RideStatus.idle;
      await tearDownHome(tester);
    });
  });

  testWidgets('the map keeps its size while the viewport height changes, '
      'and follows a new layout', (tester) async {
    await pumpHome(tester);
    final map = find.byKey(const ValueKey('home-map-layer'));
    expect(tester.getSize(map).height, 932);

    // A mobile browser's bars come in during a sheet drag.
    tester.view.physicalSize = const Size(430, 860);
    await frames(tester, 2);
    expect(tester.getSize(map).height, 932);
    tester.view.physicalSize = const Size(430, 932);
    await frames(tester, 2);
    expect(tester.getSize(map).height, 932);

    // A new width (a rotation, a resized window) is a new layout.
    tester.view.physicalSize = const Size(390, 844);
    await frames(tester, 2);
    expect(tester.getSize(map).height, 844);
    await tearDownHome(tester);
  });
}
