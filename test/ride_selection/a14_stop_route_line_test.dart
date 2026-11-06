import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart'
    show GoogleMapsFlutterPlatform;
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/app/router/routes.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/maps/routing_service.dart';
import 'package:movera_rider/core/maps/straight_line.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/presentation/finding_drivers.dart';
import 'package:movera_rider/features/ride_booking/application/trip_route_line.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';
import 'package:movera_rider/shared/widgets/custom_google_map.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fixtures/fake_maps_platform.dart';

/// A14 (owner 2026-11-05, audits/owner-2026-11-05-stop-route.png): with a
/// stop ("via Stockholm", Södertälje → Arlanda) the map drew a straight
/// line from pickup to destination that skipped the stop. The drawn line
/// must follow the road through every stop on Select ride AND on Finding
/// drivers; when a leg has no road the line is still drawn through the
/// stop, straight, and the map says "Approximate route".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pickup = LatLng(59.1955, 17.6252); // Södertälje
  const stop = LatLng(59.3293, 18.0686); // Stockholm
  const destination = LatLng(59.6498, 17.9238); // Arlanda
  const routeStop = RouteStop(
    address: 'Stockholm',
    latitude: 59.3293,
    longitude: 18.0686,
  );
  final badge = find.byKey(const ValueKey('approximate-route-badge'));
  late GoogleMapsFlutterPlatform previousPlatform;

  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    RideSnapshotStore.epoch = 0;
    FindingDriverController.active = null;
    previousPlatform = GoogleMapsFlutterPlatform.instance;
    GoogleMapsFlutterPlatform.instance = FakeMapsPlatform();
    CustomGoogleMap.debugWaitForMaps = false;
  });

  tearDown(() {
    GoogleMapsFlutterPlatform.instance = previousPlatform;
    CustomGoogleMap.debugWaitForMaps = null;
    RoutingService.defaultProvider = null;
  });

  ApiClient demoApi() => ApiClient(
    client: InProcessMockClient(),
    env: const AppEnv(flavor: AppFlavor.test, apiBaseUrl: 'https://t.invalid'),
  );

  /// A fake road router: every leg bends through three road points, unless
  /// [fails] says that leg has no road (the server's 2-point answer stays).
  RoutingService fakeRouter({bool Function(GeoPoint from)? fails}) =>
      RoutingService(
        api: demoApi(),
        allowPublicRoadFallback: true,
        isWeb: true,
        publicRoad: (from, to, {timeout = Duration.zero}) async {
          if (fails?.call(from) ?? false) return null;
          GeoPoint at(double f) => GeoPoint(
            from.latitude + (to.latitude - from.latitude) * f,
            from.longitude + (to.longitude - from.longitude) * f + 0.01,
          );
          return [from, at(0.25), at(0.5), at(0.75), to];
        },
      );

  Polyline? drawnRoute(WidgetTester tester) {
    for (final element in find.byType(GoogleMap).evaluate()) {
      for (final line in (element.widget as GoogleMap).polylines) {
        if (line.polylineId.value == 'route-casing') return line;
      }
    }
    return null;
  }

  int metresFromLine(List<LatLng> line, LatLng point) => line
      .map((p) => straightLineMeters(p, point))
      .reduce((a, b) => a < b ? a : b);

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<GlobalKey<NavigatorState>> pumpSelectRide(
    WidgetTester tester,
    RoutingService routing,
  ) async {
    phone(tester);
    RoutingService.defaultProvider = () => routing;
    final selection = RideSelectionController();
    addTearDown(selection.dispose);
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        home: const Scaffold(body: Text('a14-home')),
      ),
    );
    nav.currentState!.push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: AppRoutes.selectRide),
        builder: (_) => SelectRide(
          pickupAddress: 'Södertälje',
          destinationAddress: 'Arlanda',
          pickupPosition: pickup,
          destinationPosition: destination,
          stops: const ['Stockholm'],
          stopPoints: const [GeoPoint(59.3293, 18.0686)],
          pickupAlreadyConfirmed: true,
          selection: selection,
        ),
      ),
    );
    await settle(tester);
    return nav;
  }

  Future<GlobalKey<NavigatorState>> pumpFinding(
    WidgetTester tester,
    RoutingService routing,
  ) async {
    phone(tester);
    RoutingService.defaultProvider = () => routing;
    final api = ApiClient(client: InProcessMockClient());
    final realtime = MockRideRealtime(
      assignAfter: const Duration(days: 1),
      api: api,
    );
    addTearDown(realtime.dispose);
    final controller = FindingDriverController(realtime: realtime, api: api);
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => MaterialApp(
          navigatorKey: nav,
          home: const Scaffold(body: Text('a14-home')),
        ),
      ),
    );
    nav.currentState!.push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: AppRoutes.findingDriver),
        builder: (_) => FindingDrivers(
          pickupAddress: 'Södertälje',
          destinationAddress: 'Arlanda',
          pickupPosition: pickup,
          destinationPosition: destination,
          stops: const [routeStop],
          rideType: 'Movera',
          price: 1425,
          paymentMethod: 'Apple Pay',
          realtime: realtime,
          controller: controller,
        ),
      ),
    );
    await settle(tester);
    return nav;
  }

  void expectRoadThroughStop(Polyline? route) {
    expect(route, isNotNull, reason: 'the route is drawn');
    final points = route!.points;
    expect(points, isNot(equals(const [pickup, destination])));
    expect(points.length, greaterThan(2));
    // Road legs, not just straight segments through the stop.
    expect(points.length, greaterThan(3), reason: 'road legs are drawn');
    expect(points.first, pickup);
    expect(points.last, destination);
    expect(metresFromLine(points, stop), lessThanOrEqualTo(50));
  }

  for (final screen in ['select_ride', 'finding_drivers']) {
    Future<GlobalKey<NavigatorState>> pump(
      WidgetTester tester,
      RoutingService routing,
    ) => screen == 'select_ride'
        ? pumpSelectRide(tester, routing)
        : pumpFinding(tester, routing);

    testWidgets('$screen: one stop, the road line goes through it', (
      tester,
    ) async {
      final nav = await pump(tester, fakeRouter());
      expectRoadThroughStop(drawnRoute(tester));
      expect(badge, findsNothing, reason: 'every leg is road');
      nav.currentState!.pop();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(minutes: 10));
    });

    testWidgets('$screen: no road at all, straight through the stop, '
        'labelled approximate', (tester) async {
      final nav = await pump(tester, RoutingService(api: demoApi()));
      expect(drawnRoute(tester)!.points, const [pickup, stop, destination]);
      expect(badge, findsOneWidget);
      nav.currentState!.pop();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(minutes: 10));
    });

    testWidgets('$screen: one leg without road keeps the stop, labelled '
        'approximate', (tester) async {
      final nav = await pump(
        tester,
        fakeRouter(fails: (from) => from.latitude > 59.3),
      );
      final points = drawnRoute(tester)!.points;
      expect(points.length, greaterThan(3), reason: 'first leg is road');
      expect(points.contains(stop), isTrue, reason: 'never skips the stop');
      expect(points.last, destination);
      expect(badge, findsOneWidget);
      nav.currentState!.pop();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(minutes: 10));
    });
  }

  test('the quote distance hint goes via the stops', () {
    final direct = straightLineMeters(pickup, destination);
    final via = tripStraightMeters(pickup, const [routeStop], destination);
    expect(
      via,
      straightLineMeters(pickup, stop) + straightLineMeters(stop, destination),
    );
    expect(via, greaterThan(direct));
    expect(tripStraightMeters(pickup, const [], destination), direct);
  });
}
