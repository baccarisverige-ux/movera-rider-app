import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/features/home/application/home_controller.dart';
import 'package:movera_rider/features/home/presentation/home_map_style.dart';
import 'package:movera_rider/features/home/presentation/widgets/home_map_layer.dart';
import 'package:movera_rider/shared/widgets/custom_google_map.dart';
import 'package:movera_rider/shared/widgets/parkable_map.dart';

import '../fixtures/fake_maps_platform.dart';

/// G25 step A (BrowserStack screen-switch G-S1/G-S5, 2026-11-12): on a phone
/// every screen that covered a map swapped it for a plain box, so the Google
/// map was destroyed and a new one (a new SurfaceView) was built on the way
/// back: a beige flash and a camera jump on every switch. On native the map
/// now stays mounted while it is covered; only its owner, live location and
/// camera work pause. The web keeps its pool and its parking.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeMapsPlatform fake;
  late GoogleMapsFlutterPlatform previous;

  setUp(() {
    previous = GoogleMapsFlutterPlatform.instance;
    fake = FakeMapsPlatform();
    GoogleMapsFlutterPlatform.instance = fake;
    CustomGoogleMap.debugWaitForMaps = false;
  });

  tearDown(() {
    CustomGoogleMap.debugWaitForMaps = null;
    ParkableMap.debugKeepWhileParked = null;
    GoogleMapsFlutterPlatform.instance = previous;
  });

  group('Home', () {
    late HomeLocationController location;
    late ValueNotifier<bool> parked;

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

    Widget layer({
      void Function(GoogleMapController)? onCreated,
      void Function(GoogleMapController)? onResumed,
    }) => MaterialApp(
      home: HomeMapLayer(
        location: location,
        parked: parked,
        padding: EdgeInsets.zero,
        initialPosition: const CameraPosition(
          target: LatLng(59.3293, 18.0686),
          zoom: 14,
        ),
        mapStyle: homeMapStyle,
        onCameraMove: (_) {},
        onMapCreated: onCreated ?? (_) {},
        onMapResumed: onResumed,
      ),
    );

    testWidgets('a covered Home keeps its one map (no new platform view)', (
      tester,
    ) async {
      var created = 0;
      final resumed = <GoogleMapController>[];
      GoogleMapController? first;
      await tester.pumpWidget(
        layer(
          onCreated: (c) {
            created++;
            first = c;
          },
          onResumed: resumed.add,
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(fake.createdIds, hasLength(1));
      expect(first, isNotNull);

      // A page covers Home: parked.
      parked.value = true;
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('home-map')), findsOneWidget);
      expect(fake.disposed, isEmpty, reason: 'the map is not destroyed');

      // Home is on top again.
      parked.value = false;
      await tester.pump();
      await tester.pump();

      expect(fake.disposed, isEmpty);
      expect(fake.createdIds, hasLength(1), reason: 'no new platform view');
      expect(created, 1, reason: 'no second "map created"');
      expect(resumed, [same(first)], reason: 'Home takes its map back');

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a parked Home sends the kept map no new markers', (
      tester,
    ) async {
      await tester.pumpWidget(layer());
      await tester.pump();
      final mapWidget = tester.widget(find.byKey(const ValueKey('home-map')));

      parked.value = true;
      await tester.pump();
      // The overlays change while covered (a fix, a cleared puck).
      location.clearOverlays();
      await tester.pump();
      expect(
        identical(
          tester.widget(find.byKey(const ValueKey('home-map'))),
          mapWidget,
        ),
        isTrue,
        reason: 'the covered map is frozen: no marker work while hidden',
      );

      parked.value = false;
      await tester.pump();
      expect(
        identical(
          tester.widget(find.byKey(const ValueKey('home-map'))),
          mapWidget,
        ),
        isFalse,
        reason: 'back on top it takes the new overlays',
      );
      expect(fake.createdIds, hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('ride-stage screens (ParkableMap)', () {
    Widget host(bool parked, {VoidCallback? onResumed}) => MaterialApp(
      home: ParkableMap(
        parked: parked,
        placeholder: const ColoredBox(color: Color(0xFFF6F5F1)),
        onResumed: onResumed,
        child: const CustomGoogleMap(key: ValueKey('stage-map')),
      ),
    );

    testWidgets('a covered stage map stays mounted and paused', (tester) async {
      var resumed = 0;
      await tester.pumpWidget(host(false, onResumed: () => resumed++));
      await tester.pump();
      expect(fake.createdIds, hasLength(1));

      await tester.pumpWidget(host(true, onResumed: () => resumed++));
      await tester.pump();
      expect(find.byKey(const ValueKey('stage-map')), findsOneWidget);
      final ticking = TickerMode.valuesOf(
        tester.element(find.byKey(const ValueKey('stage-map'))),
      ).enabled;
      expect(ticking, isFalse, reason: 'no animation under a cover');

      await tester.pumpWidget(host(false, onResumed: () => resumed++));
      await tester.pump();
      expect(fake.disposed, isEmpty);
      expect(fake.createdIds, hasLength(1));
      expect(resumed, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('the web still parks: the map goes, a new one comes back', (
      tester,
    ) async {
      ParkableMap.debugKeepWhileParked = false;
      var resumed = 0;
      await tester.pumpWidget(host(false, onResumed: () => resumed++));
      await tester.pump();
      await tester.pumpWidget(host(true, onResumed: () => resumed++));
      await tester.pump();
      expect(find.byKey(const ValueKey('stage-map')), findsNothing);
      expect(fake.disposed, hasLength(1));

      await tester.pumpWidget(host(false, onResumed: () => resumed++));
      await tester.pump();
      expect(fake.createdIds, hasLength(2));
      expect(resumed, 0, reason: 'a new map attaches itself when created');
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
