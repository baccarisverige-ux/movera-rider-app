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
import 'package:movera_rider/core/location/location_repository.dart';
import 'package:movera_rider/core/maps/geo_point.dart';

/// Phase 139 moved Home's map layer out of home.dart. These pin that Home
/// still mounts one live map, and the layer's parked/caching rules.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // Item 9: Home no longer opens a made-up Stockholm map when no GPS
    // answers; these map tests start from a position this session knows.
    LocationRepository.noteSessionFix(const GeoPoint(59.3293, 18.0686));
  });
  tearDown(LocationRepository.debugForgetSessionFix);

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
    // Owner decision "Home map start": no GPS answers in tests, so the
    // map opens at the zone default once the start wait is over.
    await tester.pump(homeStartWaitLimit);

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
    testWidgets(
      'the map is told to redraw when its box grows (iOS Safari toolbar)',
      (tester) async {
        HomeMapLayer.debugRedrawRequests = 0;
        Widget sized(double height) => Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(width: 402, height: height, child: layer()),
          ),
        );
        await tester.pumpWidget(sized(420));
        await tester.pump(const Duration(seconds: 1));
        expect(HomeMapLayer.debugRedrawRequests, 0);

        // The toolbar collapses: the same map widget, a taller box.
        final before = tester.widget(mapKey);
        await tester.pumpWidget(sized(495));
        expect(identical(tester.widget(mapKey), before), isTrue);
        await tester.pump(HomeMapLayer.redrawSettle);
        await tester.pump();
        expect(HomeMapLayer.debugRedrawRequests, 1);

        // A shorter box is only clipped: no redraw.
        await tester.pumpWidget(sized(400));
        await tester.pump(const Duration(seconds: 1));
        expect(HomeMapLayer.debugRedrawRequests, 1);
      },
    );

    // 2026-11-07, owner's iPhone (Rules plan/SUMMARY / decisions session-2026-11-06): grey band on
    // Home after a trip. The box grew while the map was being created; on main the redraw was
    // dropped (`_redraw` returned at `controller == null` with no retry).
    testWidgets(
      'a redraw asked before the map exists is kept and sent once the map is ready',
      (tester) async {
        HomeMapLayer.debugRedrawRequests = 0;
        HomeMapLayer.debugMapReadyRedraws = 0;
        Widget sized(double height) => Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(width: 402, height: height, child: layer()),
          ),
        );
        await tester.pumpWidget(sized(420));
        await tester.pump(const Duration(seconds: 1));
        final state = tester.state<HomeMapLayerState>(
          find.byType(HomeMapLayer),
        );

        // The panel shrinks after the trip: a taller box before the map is ready.
        await tester.pumpWidget(sized(495));
        await tester.pump(HomeMapLayer.redrawSettle);
        await tester.pump();
        expect(HomeMapLayer.debugRedrawRequests, 1);
        expect(state.debugRedrawPending, isTrue, reason: 'kept, not dropped');

        // The map becomes ready: it is redrawn once more, after the settle time.
        state.debugMapReady();
        expect(state.debugRedrawPending, isFalse);
        expect(HomeMapLayer.debugMapReadyRedraws, 1);
        await tester.pump(HomeMapLayer.redrawSettle);
        await tester.pump();
        expect(HomeMapLayer.debugRedrawRequests, 2);
      },
    );

    testWidgets('a parked map keeps the redraw for when it comes back', (
      tester,
    ) async {
      HomeMapLayer.debugRedrawRequests = 0;
      Widget sized(double height) => Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(width: 402, height: height, child: layer()),
        ),
      );
      await tester.pumpWidget(sized(420));
      await tester.pump(const Duration(seconds: 1));
      final state = tester.state<HomeMapLayerState>(find.byType(HomeMapLayer));
      parked.value = true;
      await tester.pump();
      await tester.pumpWidget(sized(495));
      await tester.pump(HomeMapLayer.redrawSettle);
      await tester.pump();
      expect(HomeMapLayer.debugRedrawRequests, 0);
      expect(state.debugRedrawPending, isTrue);
    });
  });
}
