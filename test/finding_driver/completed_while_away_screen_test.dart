// 2026-11-27 (owner: "App rider blocked here"): the Finding screen that
// first sees a completed trip opens Ride completed. Opt-in screenshot:
// `STUCK_SHOTS=<dir> flutter test <this>`.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart'
    show GoogleMapsFlutterPlatform;
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/router/routes.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/presentation/finding_drivers.dart';
import 'package:movera_rider/features/finding_driver/presentation/searching_services.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_complete/presentation/ride_completed.dart';
import 'package:movera_rider/shared/widgets/custom_google_map.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fixtures/fake_maps_platform.dart';

final String? _dir = Platform.environment['STUCK_SHOTS'];

class _Location extends SearchingRiderLocation {
  @override
  Future<GeoPoint?> current() async => null;
  @override
  Future<GeoPoint?> request() async => null;
}

Future<void> _fonts() async {
  final flutterRoot = File(
    Platform.resolvedExecutable,
  ).parent.parent.parent.parent.parent.parent.path;
  Future<ByteData> bytes(String path) async =>
      ByteData.sublistView(File(path).readAsBytesSync());
  final roboto = FontLoader('Roboto');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    roboto.addFont(bytes('/usr/share/fonts/opentype/inter/Inter-$w.otf'));
  }
  await roboto.load();
  for (final (family, w) in [
    ('Poppins_regular', 'Regular'),
    ('Poppins_500', 'Medium'),
    ('Poppins_600', 'SemiBold'),
    ('Poppins_700', 'Bold'),
  ]) {
    await (FontLoader(
      family,
    )..addFont(bytes('/usr/share/fonts/opentype/inter/Inter-$w.otf'))).load();
  }
  await (FontLoader('MaterialIcons')..addFont(
        bytes(
          '$flutterRoot/bin/cache/artifacts/material_fonts/'
          'MaterialIcons-Regular.otf',
        ),
      ))
      .load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GoogleMapsFlutterPlatform previous;

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    if (_dir != null) await _fonts();
  });

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
  });

  Future<void> settle(WidgetTester tester, [int n = 20]) async {
    for (var i = 0; i < n; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('a trip completed while away: Finding opens Ride completed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final server = InProcessMockClient();
    final api = ApiClient(client: server);
    final realtime = MockRideRealtime(
      assignAfter: const Duration(days: 1),
      api: api,
    );
    addTearDown(realtime.dispose);
    final controller = FindingDriverController(realtime: realtime, api: api);
    final nav = GlobalKey<NavigatorState>();
    final shot = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: shot,
        child: MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            padding: EdgeInsets.only(top: 47, bottom: 34),
          ),
          child: ScreenUtilInit(
            designSize: const Size(375, 812),
            builder: (_, __) => MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(fontFamily: 'Roboto'),
              navigatorKey: nav,
              home: const Scaffold(body: Text('home')),
            ),
          ),
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
          paymentMethod: 'Cash',
          realtime: realtime,
          controller: controller,
          riderLocation: _Location(),
        ),
      ),
    );
    await settle(tester);
    expect(find.byType(FindingDrivers), findsOneWidget);
    if (_dir != null) await _write(tester, shot, 'stuck-0-finding');

    // The app comes back: the first status it sees is completed.
    realtime.emit(RideStatus.tripCompleted);
    await settle(tester, 30);

    expect(find.byType(RideCompleted), findsOneWidget);
    expect(find.byType(FindingDrivers), findsNothing);
    expect(AppScope.instance.ride.status.isCompletedSurface, isTrue);
    if (_dir != null) await _write(tester, shot, 'stuck-1-ride-completed');
  });
}

Future<void> _write(WidgetTester tester, GlobalKey key, String name) async {
  final render =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await render.toImage(pixelRatio: 2);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$_dir/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(png!.buffer.asUint8List());
  });
}
