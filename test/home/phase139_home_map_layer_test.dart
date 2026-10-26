import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/navigator_key.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/home/application/home_controller.dart';
import 'package:movera_rider/features/home/presentation/home.dart';
import 'package:movera_rider/features/home/presentation/home_map_style.dart';
import 'package:movera_rider/features/home/presentation/widgets/home_map_layer.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Phase 139 moved Home's map layer out of home.dart. These pin that Home
/// still mounts one live map, and the layer's parked/caching rules.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('Home mounts exactly one live map', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // SecureTokenStore uses a platform channel on android (flutter_test's
    // default); linux falls back to its in-memory store.
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    FindingDriverController.active = null;
    AppScope.instance.ride
      ..rideId = null
      ..status = RideStatus.idle
      ..suppressRestore = false
      ..authoritativeVersion = null
      ..authoritativeUpdatedAt = null;

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        minTextAdapt: true,
        splitScreenMode: true,
        builder: (_, __) =>
            MaterialApp(navigatorKey: moveraNavigatorKey, home: const Home()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 800));

    expect(find.byKey(const ValueKey('home-map')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    // flutter_test checks foundation debug vars before addTearDown runs.
    debugDefaultTargetPlatformOverride = null;
  });

  group('HomeMapLayer', () {
    late HomeLocationController location;
    late ValueNotifier<bool> parked;
    final mapKey = find.byKey(const ValueKey('home-map'));

    setUp(() {
      location = HomeLocationController(
        location: AppScope.instance.location,
        geocoding: AppScope.instance.geocoding,
        motion: AppScope.instance.motion,
      );
      parked = ValueNotifier(false);
    });
    tearDown(() {
      location.dispose();
      parked.dispose();
    });

    Widget layer({EdgeInsets padding = EdgeInsets.zero}) => MaterialApp(
      home: HomeMapLayer(
        location: location,
        parked: parked,
        padding: padding,
        initialPosition: const CameraPosition(
          target: LatLng(59.3293, 18.0686),
          zoom: 14,
        ),
        mapStyle: homeMapStyle,
        onCameraMove: (_) {},
        onMapCreated: (_) {},
      ),
    );

    testWidgets(
      'parked shows only the placeholder; unparking restores the map',
      (tester) async {
        parked.value = true;
        await tester.pumpWidget(layer());
        expect(mapKey, findsNothing);
        expect(
          find.byWidgetPredicate(
            (w) => w is ColoredBox && w.color == const Color(0xFFEEF1E8),
          ),
          findsOneWidget,
        );

        parked.value = false;
        await tester.pump();
        expect(mapKey, findsOneWidget);
      },
    );

    testWidgets('reuses the same map widget until overlays or padding change', (
      tester,
    ) async {
      await tester.pumpWidget(layer());
      final first = tester.widget(mapKey);

      // A parent rebuild with identical inputs must not rebuild the map.
      await tester.pumpWidget(layer());
      expect(identical(tester.widget(mapKey), first), isTrue);

      // New overlay sets (clearOverlays assigns fresh ones) must.
      location.clearOverlays();
      await tester.pump();
      final second = tester.widget(mapKey);
      expect(identical(second, first), isFalse);

      await tester.pumpWidget(
        layer(padding: const EdgeInsets.only(bottom: 10)),
      );
      expect(identical(tester.widget(mapKey), second), isFalse);
    });
  });
}
