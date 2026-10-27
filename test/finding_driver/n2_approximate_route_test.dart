import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/app/router/routes.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/maps/routing_service.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/presentation/finding_drivers.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/shared/widgets/custom_google_map.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fixtures/fake_maps_platform.dart';

/// Owner N2: without OSRM on the server, POST /routes answers with the
/// straight estimate (two points) and the searching map drew it as if it
/// were the road. The trip map already labelled such a line "Approximate
/// route"; the searching map now does too, and a real road is unlabelled.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GoogleMapsFlutterPlatform previous;

  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    RideSnapshotStore.epoch = 0;
    FindingDriverController.active = null;
    previous = GoogleMapsFlutterPlatform.instance;
    GoogleMapsFlutterPlatform.instance = FakeMapsPlatform();
    CustomGoogleMap.debugWaitForMaps = false;
  });

  tearDown(() {
    GoogleMapsFlutterPlatform.instance = previous;
    CustomGoogleMap.debugWaitForMaps = null;
    RoutingService.defaultProvider = null;
  });

  Future<void> pumpFinding(WidgetTester tester, RoutingService routing) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
          home: const Scaffold(body: Text('home')),
        ),
      ),
    );
    nav.currentState!.push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: AppRoutes.findingDriver),
        builder: (_) => FindingDrivers(
          pickupAddress: 'Klockarvägen, Bårsta',
          destinationAddress: 'Södertälje centrum',
          pickupPosition: const LatLng(59.1955, 17.6165),
          destinationPosition: const LatLng(59.2000, 17.6300),
          rideType: 'Movera',
          price: 149,
          paymentMethod: 'Apple Pay',
          realtime: realtime,
          controller: controller,
        ),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  ApiClient demoApi() => ApiClient(
    client: InProcessMockClient(),
    env: const AppEnv(flavor: AppFlavor.test, apiBaseUrl: 'https://t.invalid'),
  );

  final badge = find.byKey(const ValueKey('approximate-route-badge'));

  testWidgets('a straight answer is labelled approximate while searching', (
    tester,
  ) async {
    await pumpFinding(tester, RoutingService(api: demoApi()));
    expect(badge, findsOneWidget);
    expect(find.text('Approximate route'), findsOneWidget);
  });

  testWidgets('a road answer is not labelled', (tester) async {
    await pumpFinding(
      tester,
      RoutingService(
        api: demoApi(),
        allowPublicRoadFallback: true,
        isWeb: true,
        publicRoad: (from, to, {timeout = Duration.zero}) async => const [
          GeoPoint(59.1955, 17.6165),
          GeoPoint(59.1980, 17.6230),
          GeoPoint(59.2000, 17.6300),
        ],
      ),
    );
    expect(badge, findsNothing);
  });
}
