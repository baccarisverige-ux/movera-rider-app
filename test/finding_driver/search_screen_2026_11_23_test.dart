import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart'
    show GoogleMapsFlutterPlatform, CameraMoveEvent, CameraIdleEvent;
import 'package:movera_rider/app/router/routes.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/active_ride/application/route_change_controller.dart';
import 'package:movera_rider/features/destination_search/presentation/route_picker_page.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/presentation/finding_drivers.dart';
import 'package:movera_rider/features/finding_driver/presentation/searching_services.dart';
import 'package:movera_rider/features/finding_driver/presentation/games/search_games.dart';
import 'package:movera_rider/features/safety/presentation/ride_safety_kit.dart';
import 'package:movera_rider/features/finding_driver/presentation/share_location_sheet.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/shared/widgets/custom_google_map.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fixtures/fake_maps_platform.dart';

class _Location extends SearchingRiderLocation {
  _Location(this.fix);
  GeoPoint? fix;
  GeoPoint? afterRequest;
  int requests = 0;
  @override
  Future<GeoPoint?> current() async => fix;
  @override
  Future<GeoPoint?> request() async {
    requests++;
    fix = afterRequest;
    return fix;
  }
}

class _Editor extends SearchingPickupEditor {
  final applied = <({GeoPoint point, RouteChangeQuote? quote})>[];
  RouteChangeQuote? priced;
  @override
  Future<String?> addressAt(GeoPoint point) async => 'Sveavägen 46';
  @override
  Future<RouteChangeQuote?> quote(
    RideSnapshot ride,
    String address,
    GeoPoint point,
  ) async => priced;
  @override
  Future<RideSnapshot?> apply(
    BuildContext context,
    RideSnapshot ride,
    String address,
    GeoPoint point,
    RouteChangeQuote? quote,
  ) async {
    applied.add((point: point, quote: quote));
    return RouteChangeController.adoptMovedPickup(ride, address, point);
  }

  @override
  Future<RoutePickerMapPick?> search(BuildContext c, RideSnapshot r) async =>
      null;
}

const _pickup = LatLng(59.1955, 17.6165);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GoogleMapsFlutterPlatform previous;
  late FakeMapsPlatform maps;

  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    RideSnapshotStore.epoch = 0;
    FindingDriverController.active = null;
    previous = GoogleMapsFlutterPlatform.instance;
    maps = FakeMapsPlatform();
    GoogleMapsFlutterPlatform.instance = maps;
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

  Future<void> pumpFinding(
    WidgetTester tester, {
    required SearchingRiderLocation location,
    SearchingPickupEditor? editor,
    bool reduceMotion = false,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = ApiClient(client: InProcessMockClient());
    final realtime = MockRideRealtime(
      assignAfter: const Duration(days: 1),
      api: api,
    );
    addTearDown(realtime.dispose);
    final controller = FindingDriverController(realtime: realtime, api: api);
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(
          size: const Size(390, 844),
          disableAnimations: reduceMotion,
        ),
        child: ScreenUtilInit(
          designSize: const Size(375, 812),
          builder: (_, __) => MaterialApp(
            navigatorKey: nav,
            home: const Scaffold(body: Text('home')),
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
          pickupPosition: _pickup,
          destinationPosition: const LatLng(59.2000, 17.6300),
          rideType: 'Movera',
          price: 149,
          paymentMethod: 'Cash',
          realtime: realtime,
          controller: controller,
          riderLocation: location,
          pickupEditor: editor,
        ),
      ),
    );
    await settle(tester);
  }

  Set<Marker> markers(WidgetTester tester) =>
      tester.widget<GoogleMap>(find.byType(GoogleMap)).markers;

  Marker? marker(WidgetTester tester, String id) {
    for (final m in markers(tester)) {
      if (m.markerId.value == id) return m;
    }
    return null;
  }

  void moveCamera(LatLng target) {
    final id = maps.createdIds.last;
    maps
      ..emit(CameraMoveEvent(id, CameraPosition(target: target, zoom: 16)))
      ..emit(CameraIdleEvent(id));
  }

  testWidgets('the bottom sheet is full width with a soft upward shadow', (
    tester,
  ) async {
    await pumpFinding(tester, location: _Location(null));
    final sheet = find.byKey(const ValueKey('finding-sheet-card'));
    expect(sheet, findsOneWidget);
    expect(tester.getSize(sheet).width, 390);
    final box = tester.widget<DecoratedBox>(sheet).decoration as BoxDecoration;
    expect(
      box.borderRadius,
      const BorderRadius.vertical(top: Radius.circular(28)),
    );
    expect(box.boxShadow!.single.offset.dy, lessThan(0));
  });

  testWidgets('owner 2026-11-24: the searching sheet shows no old safety '
      'kit row (quick action + top-right button stay)', (tester) async {
    await pumpFinding(tester, location: _Location(null));
    expect(find.byType(SearchGamesRow, skipOffstage: false), findsOneWidget);
    expect(find.byType(SafetyKitSheetRow, skipOffstage: false), findsNothing);
  });

  testWidgets('known location: blue walking-man marker at the fix', (
    tester,
  ) async {
    await pumpFinding(
      tester,
      location: _Location(const GeoPoint(59.1950, 17.6150)),
    );
    final rider = marker(tester, 'rider-known');
    expect(rider, isNotNull);
    expect(rider!.position, const LatLng(59.1950, 17.6150));
    expect(marker(tester, 'rider-unknown'), isNull);
  });

  testWidgets('no location: grey marker opens the share sheet; Dela plats '
      'asks and turns the marker blue', (tester) async {
    final location = _Location(null)
      ..afterRequest = const GeoPoint(59.1950, 17.6150);
    await pumpFinding(tester, location: location);
    final grey = marker(tester, 'rider-unknown');
    expect(grey, isNotNull);
    grey!.onTap!();
    await settle(tester, 6);
    expect(find.byType(ShareLocationSheet), findsOneWidget);
    expect(find.text('Share your location'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('share-location-yes')));
    await settle(tester, 10);
    expect(location.requests, 1);
    expect(marker(tester, 'rider-known'), isNotNull);
    expect(marker(tester, 'rider-unknown'), isNull);
  });

  testWidgets('"Not now" closes the sheet without asking', (tester) async {
    final location = _Location(null);
    await pumpFinding(tester, location: location);
    marker(tester, 'rider-unknown')!.onTap!();
    await settle(tester, 6);
    await tester.tap(find.byKey(const ValueKey('share-location-no')));
    await settle(tester, 10);
    expect(location.requests, 0);
    expect(find.byType(ShareLocationSheet), findsNothing);
  });

  testWidgets('reduce motion: the share pin stands still', (tester) async {
    await pumpFinding(tester, location: _Location(null), reduceMotion: true);
    marker(tester, 'rider-unknown')!.onTap!();
    await settle(tester, 6);
    expect(find.byKey(const ValueKey('share-location-pin')), findsOneWidget);
    final top = tester.getTopLeft(
      find.byKey(const ValueKey('share-location-pin')),
    );
    await tester.pump(const Duration(milliseconds: 700));
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('share-location-pin'))),
      top,
    );
  });

  testWidgets('pickup is locked: moving the map never moves it; Justera '
      'pill sits on it', (tester) async {
    await pumpFinding(tester, location: _Location(null), editor: _Editor());
    expect(marker(tester, 'pickup-adjust')!.position, _pickup);
    moveCamera(const LatLng(59.20, 17.62));
    await settle(tester, 4);
    // The Justera pill sits on the locked pickup pin.
    expect(marker(tester, 'pickup-adjust')!.position, _pickup);
    expect(find.byKey(const ValueKey('pickup-edit-card')), findsNothing);
  });

  testWidgets('Justera: a small move confirms the same-price move and '
      'locks again', (tester) async {
    final editor = _Editor();
    await pumpFinding(tester, location: _Location(null), editor: editor);
    marker(tester, 'pickup-adjust')!.onTap!();
    await settle(tester, 6);
    expect(find.byKey(const ValueKey('pickup-edit-card')), findsOneWidget);
    expect(find.text('Move the map to move the pin'), findsOneWidget);
    expect(find.byKey(const ValueKey('pickup-edit-pin')), findsOneWidget);
    expect(marker(tester, 'pickup-adjust'), isNull);
    final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
    expect(map.circles.single.radius, greaterThan(0));
    const near = LatLng(59.1960, 17.6170);
    moveCamera(near);
    await settle(tester, 6);
    expect(find.text('Sveavägen 46'), findsWidgets);
    expect(find.text('Confirm pickup'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pickup-edit-confirm')));
    await settle(tester, 6);
    expect(editor.applied.single.quote, isNull);
    expect(editor.applied.single.point.latitude, 59.1960);
    expect(editor.applied.single.point.longitude, 17.6170);
    expect(find.byKey(const ValueKey('pickup-edit-card')), findsNothing);
    expect(marker(tester, 'pickup-adjust')!.position, near);
  });

  testWidgets('Justera: beyond the free zone shows +N and the new price; '
      'confirm uses that quote', (tester) async {
    final editor = _Editor()
      ..priced = RouteChangeQuote(
        pickupAddress: 'Sveavägen 52',
        pickupPoint: const GeoPoint(59.2100, 17.6165),
        destinationAddress: 'Södertälje centrum',
        destinationPoint: const GeoPoint(59.2, 17.63),
        stops: const [],
        oldPriceKr: 149,
        newPriceKr: 165,
        currency: 'SEK',
      );
    await pumpFinding(tester, location: _Location(null), editor: editor);
    marker(tester, 'pickup-adjust')!.onTap!();
    await settle(tester, 6);
    moveCamera(const LatLng(59.2100, 17.6165));
    await settle(tester, 6);
    expect(find.byKey(const ValueKey('pickup-edit-extra')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('pickup-edit-price-line')),
      findsOneWidget,
    );
    expect(find.text('Confirm new price'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pickup-edit-confirm')));
    await settle(tester, 6);
    expect(editor.applied.single.quote, same(editor.priced));
  });

  testWidgets('Justera: ✕ cancels and leaves the pickup', (tester) async {
    final editor = _Editor();
    await pumpFinding(tester, location: _Location(null), editor: editor);
    marker(tester, 'pickup-adjust')!.onTap!();
    await settle(tester, 6);
    moveCamera(const LatLng(59.1960, 17.6170));
    await settle(tester, 6);
    await tester.tap(find.byKey(const ValueKey('pickup-edit-close')));
    await settle(tester, 6);
    expect(editor.applied, isEmpty);
    expect(find.byKey(const ValueKey('pickup-edit-card')), findsNothing);
    // The Justera pill sits on the locked pickup pin.
    expect(marker(tester, 'pickup-adjust')!.position, _pickup);
  });

  testWidgets('pulled-up sheet: three round quick actions', (tester) async {
    await pumpFinding(tester, location: _Location(null));
    for (final key in ['qa-add-stop', 'qa-saved-places', 'qa-safety-kit']) {
      expect(find.byKey(ValueKey(key), skipOffstage: false), findsOneWidget);
    }
    expect(find.text('Add stop', skipOffstage: false), findsOneWidget);
    // Owner 2026-11-23: the two games swipe row under the round buttons.
    expect(
      find.byKey(const ValueKey('search-games-row'), skipOffstage: false),
      findsOneWidget,
    );
  });
}
