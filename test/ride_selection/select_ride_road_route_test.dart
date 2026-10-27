import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/router/routes.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/maps/map_camera_motion.dart';
import 'package:movera_rider/core/maps/map_owners.dart';
import 'package:movera_rider/core/maps/routing_service.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeMap extends Fake implements GoogleMapController {
  int moves = 0;

  @override
  Future<void> animateCamera(CameraUpdate cameraUpdate, {Duration? duration}) {
    moves += 1;
    return Future<void>.value();
  }

  @override
  Future<void> moveCamera(CameraUpdate cameraUpdate) {
    moves += 1;
    return Future<void>.value();
  }
}

/// uat-r1 (owner's iPhone report): Select Ride drew its own straight
/// pickup → destination line and never asked the routing seam for the road,
/// so even with road geometry available the map showed a straight line.
/// The straight line is only the first paint; the road route replaces it
/// when the provider answers, also when it answers late.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pickup = LatLng(59.1955, 17.6165);
  const destination = LatLng(59.2000, 17.6300);
  const road = [
    GeoPoint(59.1955, 17.6165),
    GeoPoint(59.1970, 17.6200),
    GeoPoint(59.1990, 17.6260),
    GeoPoint(59.2000, 17.6300),
  ];

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() {
    RoutingService.defaultProvider = null;
  });

  Polyline? casing(WidgetTester tester) {
    final maps = find.byType(GoogleMap);
    if (maps.evaluate().isEmpty) return null;
    for (final line in tester.widget<GoogleMap>(maps).polylines) {
      if (line.polylineId.value == 'route-casing') return line;
    }
    return null;
  }

  testWidgets('the Select Ride map draws the road route once the provider '
      'answers, straight line only until then', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // The demo transport (two points) completed by a road router that
    // answers after a while, as on a phone network.
    var asked = 0;
    final routing = RoutingService(
      api: ApiClient(
        client: InProcessMockClient(),
        env: const AppEnv(
          flavor: AppFlavor.test,
          apiBaseUrl: 'https://t.invalid',
        ),
      ),
      allowPublicRoadFallback: true,
      isWeb: true,
      publicRoad: (from, to, {timeout = Duration.zero}) async {
        asked += 1;
        await Future<void>.delayed(const Duration(seconds: 3));
        return road;
      },
    );
    RoutingService.defaultProvider = () => routing;

    final selection = RideSelectionController();
    addTearDown(selection.dispose);
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        home: const Scaffold(body: Text('road-home')),
      ),
    );
    nav.currentState!.push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: AppRoutes.selectRide),
        builder: (_) => SelectRide(
          pickupAddress: 'Klockarvägen, Bårsta',
          destinationAddress: 'Södertälje centrum',
          pickupPosition: pickup,
          destinationPosition: destination,
          pickupAlreadyConfirmed: true,
          selection: selection,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    for (var i = 0; i < 10 && casing(tester) == null; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final first = casing(tester);
    expect(first, isNotNull, reason: 'the live map with its route is up');
    expect(first!.points.length, 2, reason: 'straight line as first paint');
    expect(asked, 1, reason: 'the road was asked for at once');

    // The provider answers late: the line is redrawn, not left straight.
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 100));
    expect(casing(tester)!.points.length, road.length);
    expect(casing(tester)!.points.first, pickup);
    expect(casing(tester)!.points.last, destination);
    expect(
      find.byKey(const ValueKey('approximate-route-badge')),
      findsNothing,
      reason: 'a road route is not approximate',
    );

    // Leave the screen with its timers cleaned up.
    nav.currentState!.pop();
    await tester.pump(const Duration(seconds: 1));
  });

  // Owner N6: on Select ride the camera snapped back under the rider. The
  // road route answers late (a sleeping server, a slow router); when it
  // came after the rider had pinched or panned, its refit flew the camera
  // back to the overview. A late road keeps the rider's camera.
  testWidgets('a road that answers after a hand move does not refit', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final routing = RoutingService(
      api: ApiClient(
        client: InProcessMockClient(),
        env: const AppEnv(
          flavor: AppFlavor.test,
          apiBaseUrl: 'https://t.invalid',
        ),
      ),
      allowPublicRoadFallback: true,
      isWeb: true,
      publicRoad: (from, to, {timeout = Duration.zero}) async {
        await Future<void>.delayed(const Duration(seconds: 3));
        return road;
      },
    );
    RoutingService.defaultProvider = () => routing;
    final fits = <GeoPoint>[];
    final maps = AppScope.instance.maps;
    maps.debugOnFitBounds = (_, a, __) => fits.add(a);
    addTearDown(() {
      maps
        ..debugOnFitBounds = null
        ..detach(owner: MapOwners.selectRide);
    });
    final selection = RideSelectionController();
    addTearDown(selection.dispose);
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        home: const Scaffold(body: Text('road-home')),
      ),
    );
    nav.currentState!.push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: AppRoutes.selectRide),
        builder: (_) => SelectRide(
          pickupAddress: 'Klockarvägen, Bårsta',
          destinationAddress: 'Södertälje centrum',
          pickupPosition: pickup,
          destinationPosition: destination,
          pickupAlreadyConfirmed: true,
          selection: selection,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    // The rider's map, which they have just pinched.
    final map = _FakeMap();
    maps.attach(map, owner: MapOwners.selectRide);
    mapViewOf(map).movedByHandAt = DateTime.now();
    fits.clear();

    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 300));
    expect(casing(tester)!.points.length, road.length, reason: 'road drawn');
    expect(fits, isEmpty, reason: 'the rider\'s camera is kept');
    expect(map.moves, 0);

    nav.currentState!.pop();
    await tester.pump(const Duration(seconds: 1));
  });

  // Owner N2: without OSRM the server answers /routes with its straight
  // estimate (two points). The line is then only the direct line; the map
  // says so, as the trip map does, instead of passing it off as the road.
  testWidgets('a straight answer from the server is labelled approximate', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // The in-process transport answers with the two end points only.
    final routing = RoutingService(
      api: ApiClient(
        client: InProcessMockClient(),
        env: const AppEnv(
          flavor: AppFlavor.test,
          apiBaseUrl: 'https://t.invalid',
        ),
      ),
    );
    RoutingService.defaultProvider = () => routing;
    final selection = RideSelectionController();
    addTearDown(selection.dispose);
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        home: const Scaffold(body: Text('road-home')),
      ),
    );
    nav.currentState!.push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: AppRoutes.selectRide),
        builder: (_) => SelectRide(
          pickupAddress: 'Klockarvägen, Bårsta',
          destinationAddress: 'Södertälje centrum',
          pickupPosition: pickup,
          destinationPosition: destination,
          pickupAlreadyConfirmed: true,
          selection: selection,
        ),
      ),
    );
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(casing(tester)!.points.length, 2);
    expect(
      find.byKey(const ValueKey('approximate-route-badge')),
      findsOneWidget,
    );
    expect(find.text('Approximate route'), findsOneWidget);

    nav.currentState!.pop();
    await tester.pump(const Duration(seconds: 1));
  });
}
