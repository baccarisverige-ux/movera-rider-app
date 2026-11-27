import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:http/http.dart' as http;
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/navigator_key.dart';
import 'package:movera_rider/app/router/routes.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/feature_flags/feature_flags.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/maps/map_owners.dart';
import 'package:movera_rider/core/maps/routing_service.dart';
import 'package:movera_rider/features/booking/application/booking_controller.dart';
import 'package:movera_rider/features/booking/application/booking_coordinator.dart';
import 'package:movera_rider/features/booking/data/booking_repository.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/pickup/presentation/set_pickup_page.dart';
import 'package:movera_rider/features/ride_booking/data/api_quote_repository.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/active_trip_repository.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fixtures/fake_maps_platform.dart';

/// Holds the booking POST open until [release]; with [fail] it answers 500.
class _HeldBookClient extends InProcessMockClient {
  final Completer<void> release = Completer<void>();
  bool fail = false;
  Map<String, dynamic>? body;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method.toUpperCase() == 'POST' &&
        request.url.path == '/api/v1/rides') {
      if (request is http.Request) {
        body = jsonDecode(request.body) as Map<String, dynamic>;
      }
      await release.future;
      if (fail) {
        return http.StreamedResponse(
          Stream.value(utf8.encode('{"code":"internal","message":"down"}')),
          500,
          headers: {'content-type': 'application/json'},
        );
      }
    }
    return super.send(request);
  }
}

/// Like the real plugin: a camera command on a map makes that map report
/// a camera move and then idle.
class _EchoMaps extends FakeMapsPlatform {
  bool echo = false;
  LatLng echoTarget = const LatLng(59.49, 17.99);
  final List<int> echoed = [];

  Future<void> _echo(int mapId) async {
    if (!echo) return;
    echoed.add(mapId);
    emit(CameraMoveStartedEvent(mapId));
    emit(CameraMoveEvent(mapId, CameraPosition(target: echoTarget, zoom: 9)));
    emit(CameraIdleEvent(mapId));
  }

  @override
  Future<void> animateCamera(CameraUpdate u, {required int mapId}) async {
    await super.animateCamera(u, mapId: mapId);
    await _echo(mapId);
  }

  @override
  Future<void> animateCameraWithConfiguration(
    CameraUpdate u,
    CameraUpdateAnimationConfiguration c, {
    required int mapId,
  }) async {
    await super.animateCamera(u, mapId: mapId);
    await _echo(mapId);
  }

  @override
  Future<void> moveCamera(CameraUpdate u, {required int mapId}) async {
    await super.moveCamera(u, mapId: mapId);
    await _echo(mapId);
  }
}

class _NoTrip implements ActiveTripRepository {
  @override
  Future<RideSnapshot?> fetchActive() async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  late GoogleMapsFlutterPlatform previous;
  setUp(() {
    previous = GoogleMapsFlutterPlatform.instance;
    SharedPreferences.setMockInitialValues({});
    RideSnapshotStore.epoch = 0;
    FindingDriverController.active = null;
    AppScope.instance.ride
      ..rideId = null
      ..status = RideStatus.idle
      ..suppressRestore = false
      ..authoritativeVersion = null
      ..authoritativeUpdatedAt = null;
  });
  tearDown(() {
    GoogleMapsFlutterPlatform.instance = previous;
    RoutingService.defaultProvider = null;
    AppScope.instance.maps.debugOnFitBounds = null;
  });

  /// Opens Select ride, then Set pickup from "Select Movera"; returns the
  /// held booking client and the owners of every fit after [watch] is set.
  Future<({_HeldBookClient transport, List<String?> fits, _EchoMaps platform})>
  openSetPickup(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final platform = _EchoMaps();
    GoogleMapsFlutterPlatform.instance = platform;
    const pickup = LatLng(59.3300, 18.0590);
    const destination = LatLng(59.6519, 17.9186);
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
        await Future<void>.delayed(const Duration(seconds: 1));
        return [
          GeoPoint(from.latitude, from.longitude),
          const GeoPoint(59.50, 17.99),
          GeoPoint(to.latitude, to.longitude),
        ];
      },
    );
    RoutingService.defaultProvider = () => routing;
    final fits = <String?>[];
    AppScope.instance.maps.debugOnFitBounds = (owner, a, b) => fits.add(owner);
    final transport = _HeldBookClient();
    final api = ApiClient(client: transport);
    final selection = RideSelectionController(
      quotes: ApiQuoteRepository(api: api),
      flags: const FeatureFlags(),
    );
    addTearDown(selection.dispose);
    final booking = BookingController(
      store: BookingRepository(coordinator: BookingCoordinator(api: api)),
    );
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(375, 812),
        minTextAdapt: true,
        splitScreenMode: true,
        builder: (_, __) => MaterialApp(
          navigatorKey: moveraNavigatorKey,
          home: const Scaffold(body: Center(child: Text('home'))),
        ),
      ),
    );
    moveraNavigatorKey.currentState!.push(
      RideStageTransition(
        SelectRide(
          pickupAddress: 'Stockholm Central',
          destinationAddress: 'Arlanda Airport',
          pickupPosition: pickup,
          destinationPosition: destination,
          pickupAlreadyConfirmed: true,
          selection: selection,
          booking: booking,
          activeTrips: _NoTrip(),
        ),
        settings: const RouteSettings(name: AppRoutes.selectRide),
      ),
    );
    await tester.pump();
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text('Select Movera'));
    await tester.pump();
    for (
      var i = 0;
      i < 30 && find.byType(SetPickupPage).evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(AppScope.instance.maps.activeOwner, MapOwners.pickup);
    fits.clear();
    return (transport: transport, fits: fits, platform: platform);
  }

  Future<void> pumpFor(WidgetTester tester, int tenths) async {
    for (var i = 0; i < tenths; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('back from Set pickup: Select ride frames its route again', (
    tester,
  ) async {
    final s = await openSetPickup(tester);
    await moveraNavigatorKey.currentState!.maybePop();
    await pumpFor(tester, 30);
    // ignore: avoid_print
    print(
      'PROOF back: owner=${AppScope.instance.maps.activeOwner} '
      'fits=${s.fits}',
    );
    expect(find.byType(SetPickupPage), findsNothing);
    expect(AppScope.instance.maps.activeOwner, MapOwners.selectRide);
    expect(s.fits, contains(MapOwners.selectRide));
    expect(s.fits.where((o) => o == MapOwners.pickup), isEmpty);
    s.transport.release.complete();
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('booking fails after Confirm and search: Set pickup closes '
      'and Select ride frames its route again', (tester) async {
    final s = await openSetPickup(tester);
    s.transport.fail = true;
    await tester.tap(find.text('Confirm and search'));
    await pumpFor(tester, 20);
    expect(
      s.fits.where((o) => o == MapOwners.pickup),
      isEmpty,
      reason: 'no fit on the held Set pickup map',
    );
    s.transport.release.complete();
    await pumpFor(tester, 40);
    // ignore: avoid_print
    print(
      'PROOF booking failed: owner=${AppScope.instance.maps.activeOwner} '
      'setPickup=${find.byType(SetPickupPage).evaluate().length} '
      'fits=${s.fits}',
    );
    expect(find.byType(SetPickupPage), findsNothing);
    expect(AppScope.instance.maps.activeOwner, MapOwners.selectRide);
    expect(s.fits, contains(MapOwners.selectRide));
    await tester.pump(const Duration(seconds: 5));
  });
}
