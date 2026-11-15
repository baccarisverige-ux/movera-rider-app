import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/navigator_key.dart';
import 'package:movera_rider/core/location/geocoding_repository.dart';
import 'package:movera_rider/core/location/location_repository.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/home/application/home_controller.dart';
import 'package:movera_rider/features/home/application/saved_place_pins.dart';
import 'package:movera_rider/features/home/presentation/home.dart';
import 'package:movera_rider/features/home/presentation/home_map_style.dart';
import 'package:movera_rider/features/home/presentation/widgets/home_map_layer.dart';
import 'package:movera_rider/shared/widgets/custom_google_map.dart';
import 'package:movera_rider/shared/widgets/saved_place_pin_marker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fixtures/fake_maps_platform.dart';

/// BQ-V11 (owner 2026-10-31 / 2026-11-01, Rules
/// conversation/session-2026-10-30c.md:66, :70, :83 and
/// plan/rider-saved-pins/SPEC.md): the rider's saved places (Home, Work,
/// Gym, a star for any other) are small logo pins on Home's map, only once
/// saved; a tap opens the car categories with that place.
List<Marker> _savedMarkers(FakeMapsPlatform fake) => [
  for (final entry in fake.markers.entries)
    if (entry.key.value.startsWith('saved_place_')) entry.value,
];

class _Geocoder implements GeocodingRepository {
  _Geocoder(this.points);
  final Map<String, GeoPoint> points;
  final List<String> asked = [];

  @override
  Future<PlaceResult?> forward(String query) async {
    asked.add(query);
    final point = points[query];
    return point == null ? null : PlaceResult(address: query, point: point);
  }

  @override
  Future<String?> reverse(GeoPoint point) async => null;
}

/// A drawer that remembers which picture and frame each icon is.
class _Drawer {
  final Map<
    BitmapDescriptor,
    ({SavedPinStyle style, String label, double grow, double labelOpacity})
  >
  drawn = {};

  Future<SavedPinVisual> call(
    SavedPinStyle style,
    String label, {
    required double grow,
    required double labelOpacity,
  }) async {
    final icon = BitmapDescriptor.bytes(
      Uint8List.fromList([drawn.length, style.index]),
      width: 40,
      height: 70,
    );
    drawn[icon] = (
      style: style,
      label: label,
      grow: grow,
      labelOpacity: labelOpacity,
    );
    return (icon: icon, anchor: const Offset(0.5, 0.8));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  late FakeMapsPlatform fake;
  late GoogleMapsFlutterPlatform previous;

  setUp(() {
    previous = GoogleMapsFlutterPlatform.instance;
    fake = FakeMapsPlatform();
    GoogleMapsFlutterPlatform.instance = fake;
    CustomGoogleMap.debugWaitForMaps = false;
    SavedPlacePins.debugClearPositions();
  });

  tearDown(() {
    CustomGoogleMap.debugWaitForMaps = null;
    GoogleMapsFlutterPlatform.instance = previous;
  });

  group('Home map layer', () {
    late HomeLocationController location;
    late ValueNotifier<bool> parked;
    late _Geocoder geocoder;
    late _Drawer drawer;
    late SavedPlacePins pins;
    var reduceMotion = false;

    const homeAt = GeoPoint(59.33, 18.06);
    const workAt = GeoPoint(59.34, 18.07);
    const gymAt = GeoPoint(59.35, 18.08);
    const kioskAt = GeoPoint(59.36, 18.09);
    const newHomeAt = GeoPoint(59.31, 18.02);

    const home = SavedPlacePinEntry(
      key: 'home',
      kind: 'home',
      title: 'Home',
      address: 'Home street 1',
      target: 'home',
    );
    const work = SavedPlacePinEntry(
      key: 'work',
      kind: 'office',
      title: 'Work',
      address: 'Work street 2',
      target: 'work',
    );
    const gym = SavedPlacePinEntry(
      key: 'place_gym',
      kind: 'gym',
      title: 'Gym',
      address: 'Gym street 3',
      target: 'custom',
      customType: 'gym',
    );
    const kiosk = SavedPlacePinEntry(
      key: 'place_kiosk',
      kind: 'mall',
      title: 'Kiosk',
      address: 'Kiosk street 4',
      target: 'custom',
      customType: 'mall',
    );

    setUp(() {
      reduceMotion = false;
      location = HomeLocationController(
        location: AppScope.instance.location,
        geocoding: AppScope.instance.geocoding,
        motion: AppScope.instance.motion,
      );
      parked = ValueNotifier(false);
      geocoder = _Geocoder({
        home.address: homeAt,
        work.address: workAt,
        gym.address: gymAt,
        kiosk.address: kioskAt,
        'New home 9': newHomeAt,
      });
      drawer = _Drawer();
      pins = SavedPlacePins(
        geocoding: geocoder,
        draw: drawer.call,
        reduceMotion: () => reduceMotion,
      );
    });
    tearDown(() {
      pins.dispose();
      location.dispose();
      parked.dispose();
    });

    Widget layer() => MaterialApp(
      home: HomeMapLayer(
        location: location,
        savedPins: pins,
        parked: parked,
        padding: EdgeInsets.zero,
        initialPosition: const CameraPosition(
          target: LatLng(59.3293, 18.0686),
          zoom: 14,
        ),
        mapStyle: homeMapStyle,
        onCameraMove: (_) {},
        onMapCreated: (_) {},
      ),
    );

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    ({SavedPinStyle style, String label, double grow, double labelOpacity})
    drawnOf(Marker marker) => drawer.drawn[marker.icon]!;

    testWidgets('no saved place: no pin (SPEC 1)', (tester) async {
      await tester.pumpWidget(layer());
      await pins.show(const []);
      await settle(tester);
      expect(_savedMarkers(fake), isEmpty);
      expect(geocoder.asked, isEmpty);
    });

    testWidgets('Home, Work, Gym and any other place: one pin each, on its '
        'address, with its own picture and name (SPEC 2, 7, owner "No thats '
        'enouth for pin")', (tester) async {
      await tester.pumpWidget(layer());
      await tester.pump();
      await pins.show(const [home, work, gym, kiosk]);
      await settle(tester);

      final markers = {
        for (final m in _savedMarkers(fake)) m.markerId.value: m,
      };
      expect(markers.keys, {
        'saved_place_home',
        'saved_place_work',
        'saved_place_place_gym',
        'saved_place_place_kiosk',
      });
      expect(markers['saved_place_home']!.position, const LatLng(59.33, 18.06));
      expect(markers['saved_place_work']!.position, const LatLng(59.34, 18.07));
      expect(
        markers['saved_place_place_gym']!.position,
        const LatLng(59.35, 18.08),
      );
      expect(
        markers['saved_place_place_kiosk']!.position,
        const LatLng(59.36, 18.09),
      );

      final styles = {
        for (final e in markers.entries) e.key: drawnOf(e.value).style,
      };
      expect(styles, {
        'saved_place_home': SavedPinStyle.home,
        'saved_place_work': SavedPinStyle.work,
        'saved_place_place_gym': SavedPinStyle.gym,
        'saved_place_place_kiosk': SavedPinStyle.star,
      });
      for (final m in markers.values) {
        final drawn = drawnOf(m);
        expect(drawn.grow, 1, reason: 'at rest after the animation');
        expect(drawn.labelOpacity, 1, reason: 'the name is shown');
        expect(m.rotation, 0);
        expect(
          m.anchor,
          const Offset(0.5, 0.8),
          reason: 'the point on the spot',
        );
        expect(m.consumeTapEvents, isTrue);
        expect(m.zIndexInt, SavedPlacePins.zIndex);
      }
      expect(drawnOf(markers['saved_place_place_kiosk']!).label, 'Kiosk');
      expect(
        {for (final m in markers.values) m.icon}.length,
        4,
        reason: 'four different icons',
      );
    });

    testWidgets('a new place grows from the ground, bounces, shakes, then the '
        'name fades in (SPEC 3)', (tester) async {
      await tester.pumpWidget(layer());
      await tester.pump();
      await pins.show(const []);
      final seen = <({double grow, double rotation, double label})>[];
      void record() {
        for (final m in pins.markers) {
          final d = drawnOf(m);
          seen.add((grow: d.grow, rotation: m.rotation, label: d.labelOpacity));
        }
      }

      pins.addListener(record);
      await pins.show(const [home]);
      await settle(tester);
      pins.removeListener(record);

      expect(seen.first.grow, lessThan(0.5), reason: 'starts on the ground');
      expect(
        seen.map((f) => f.grow).reduce((a, b) => a > b ? a : b),
        greaterThan(1),
        reason: 'small bounce',
      );
      expect(
        seen.where((f) => f.rotation != 0),
        isNotEmpty,
        reason: 'one tiny shake',
      );
      expect(
        seen.every((f) => f.rotation.abs() <= 6),
        isTrue,
        reason: 'very small',
      );
      final firstLabel = seen.indexWhere((f) => f.label > 0);
      final lastShake = seen.lastIndexWhere((f) => f.rotation != 0);
      expect(firstLabel, greaterThan(lastShake), reason: 'label after');
      expect(seen.last, (grow: 1.0, rotation: 0.0, label: 1.0));
      expect(_savedMarkers(fake), hasLength(1));
    });

    testWidgets('edit moves the pin, delete removes it (SPEC 4, 5)', (
      tester,
    ) async {
      await tester.pumpWidget(layer());
      await tester.pump();
      await pins.show(const [home, work]);
      await settle(tester);
      expect(_savedMarkers(fake), hasLength(2));

      const moved = SavedPlacePinEntry(
        key: 'home',
        kind: 'home',
        title: 'Home',
        address: 'New home 9',
        target: 'home',
      );
      await pins.show(const [moved, work]);
      await settle(tester);
      final homePin = fake.markers[SavedPlacePins.markerIdFor('home')]!;
      expect(homePin.position, const LatLng(59.31, 18.02));
      expect(_savedMarkers(fake), hasLength(2));

      await pins.show(const [moved]);
      await settle(tester);
      expect(_savedMarkers(fake).map((m) => m.markerId.value), [
        'saved_place_home',
      ]);

      await pins.show(const []);
      await settle(tester);
      expect(_savedMarkers(fake), isEmpty);
    });

    testWidgets('an address without a position gets no pin (never a guess)', (
      tester,
    ) async {
      await tester.pumpWidget(layer());
      await tester.pump();
      await pins.show(const [
        SavedPlacePinEntry(
          key: 'home',
          kind: 'home',
          title: 'Home',
          address: 'Nowhere 0',
          target: 'home',
        ),
      ]);
      await settle(tester);
      expect(_savedMarkers(fake), isEmpty);
    });

    testWidgets('reduced motion: the pin just appears', (tester) async {
      reduceMotion = true;
      await tester.pumpWidget(layer());
      await tester.pump();
      await pins.show(const [gym]);
      await tester.pump();
      final markers = _savedMarkers(fake);
      expect(markers, hasLength(1));
      expect(drawnOf(markers.single).grow, 1);
      expect(drawer.drawn, hasLength(1), reason: 'one frame only');
      await settle(tester);
    });

    testWidgets('a tap on a pin hands its place to Home (SPEC 8)', (
      tester,
    ) async {
      final tapped = <SavedPlacePinEntry>[];
      pins.onTap = tapped.add;
      await tester.pumpWidget(layer());
      await tester.pump();
      await pins.show(const [home, gym]);
      await settle(tester);

      fake.emit(
        MarkerTapEvent(
          fake.createdIds.single,
          SavedPlacePins.markerIdFor('place_gym'),
        ),
      );
      await tester.pump();
      expect(tapped, [gym]);
    });
  });

  group('the pictures', () {
    test(
      'each style is drawn, different, with the point at the anchor',
      () async {
        final images = <SavedPinStyle, Uint8List>{};
        for (final style in SavedPinStyle.values) {
          final result = await SavedPlacePinMarker.createVisual(
            style,
            'Home',
            pixelRatio: 1,
          );
          final image = result.image;
          expect(image.width, greaterThanOrEqualTo(SavedPlacePinMarker.width));
          final anchor = result.visual.anchor;
          expect(anchor.dx, closeTo(0.5, 0.01));
          expect(
            anchor.dy,
            inInclusiveRange(0.6, 0.9),
            reason: 'the point, with the name under it',
          );
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!.buffer.asUint8List();
          images[style] = bytes;
          // The drop's middle is painted (not see-through).
          final cx = (image.width / 2).round();
          final cy = (anchor.dy * image.height * 0.55).round();
          expect(bytes[(cy * image.width + cx) * 4 + 3], greaterThan(200));
          image.dispose();
        }
        final distinct = images.values.map((b) => Object.hashAll(b)).toSet();
        expect(distinct, hasLength(SavedPinStyle.values.length));
      },
    );

    test('kinds pick the pictures: home, work, gym, star for the rest', () {
      expect(savedPinStyleFor('home'), SavedPinStyle.home);
      expect(savedPinStyleFor('office'), SavedPinStyle.work);
      expect(savedPinStyleFor('work'), SavedPinStyle.work);
      expect(savedPinStyleFor('gym'), SavedPinStyle.gym);
      for (final other in [
        'mall',
        'school',
        'airport',
        'family',
        'other',
        '',
      ]) {
        expect(savedPinStyleFor(other), SavedPinStyle.star);
      }
    });
  });

  group('Home', () {
    setUp(() {
      LocationRepository.noteSessionFix(const GeoPoint(59.3293, 18.0686));
    });
    tearDown(LocationRepository.debugForgetSessionFix);

    Future<void> pumpHome(WidgetTester tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          minTextAdapt: true,
          splitScreenMode: true,
          builder: (_, __) =>
              MaterialApp(navigatorKey: moveraNavigatorKey, home: const Home()),
        ),
      );
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('the saved places of the rider are pins on the map', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'movera_home_address': 'Sveavägen 10, Stockholm',
        'movera_work_address': 'Kungsgatan 5, Stockholm',
        'movera_saved_places':
            '[{"id":"place_g1","title":"gym","type":"gym","address":"Fridhemsgatan 3, Stockholm"},'
            '{"id":"place_m1","title":"Mamma","type":"family","address":"Ringvägen 7, Stockholm"}]',
      });
      await pumpHome(tester);

      final ids = {for (final m in _savedMarkers(fake)) m.markerId.value};
      expect(ids, {
        'saved_place_home',
        'saved_place_work',
        'saved_place_place_g1',
        'saved_place_place_m1',
      });
      final icons = {for (final m in _savedMarkers(fake)) m.icon};
      expect(icons, hasLength(4), reason: 'a picture per place');
      for (final m in _savedMarkers(fake)) {
        expect(
          m.icon,
          isA<BytesMapBitmap>(),
          reason: 'Movera-drawn, not Google red',
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('no saved place: no pin on the map', (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await pumpHome(tester);
      expect(fake.createdIds, isNotEmpty, reason: 'the map is there');
      expect(_savedMarkers(fake), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    });
  });
}
