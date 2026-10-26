import 'dart:async';

import 'package:movera_rider/features/pickup/presentation/set_pickup_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/navigator_key.dart';
import 'package:movera_rider/app/router/routes.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/core/feature_flags/feature_flags.dart';
import 'package:movera_rider/features/booking/application/booking_controller.dart';
import 'package:movera_rider/features/booking/application/booking_coordinator.dart';
import 'package:movera_rider/features/booking/data/booking_repository.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/presentation/finding_drivers.dart';
import 'package:movera_rider/features/ride_booking/data/api_quote_repository.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RecordingObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushed = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
  }
}

class _GateRideCreateClient extends InProcessMockClient {
  final Completer<void> rideCreateStarted = Completer<void>();
  final Completer<void> allowRideCreate = Completer<void>();
  int rideCreateCalls = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method.toUpperCase() == 'POST' &&
        request.url.path == '/api/v1/rides') {
      rideCreateCalls += 1;
      if (!rideCreateStarted.isCompleted) rideCreateStarted.complete();
      await allowRideCreate.future;
    }
    return super.send(request);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
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

  /// Book now opens Set pickup first; confirm it to start the request.
  Future<void> confirmSetPickup(WidgetTester tester) async {
    for (
      var i = 0;
      i < 30 && find.byType(SetPickupPage).evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(SetPickupPage), findsOneWidget);
    await tester.tap(find.text('Confirm and search'));
    for (
      var i = 0;
      i < 10 && find.byType(SetPickupPage).evaluate().isNotEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets(
    'created ride is surfaced when Select Ride disappears during submitFinding',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final transport = _GateRideCreateClient();
      final api = ApiClient(client: transport);
      final selection = RideSelectionController(
        quotes: ApiQuoteRepository(api: api),
        flags: const FeatureFlags(),
      );
      addTearDown(selection.dispose);
      final booking = BookingController(
        store: BookingRepository(coordinator: BookingCoordinator(api: api)),
      );
      final observer = _RecordingObserver();

      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(375, 812),
          minTextAdapt: true,
          splitScreenMode: true,
          builder: (_, __) => MaterialApp(
            navigatorKey: moveraNavigatorKey,
            navigatorObservers: [observer],
            home: const Scaffold(body: Center(child: Text('phase55-home'))),
          ),
        ),
      );

      moveraNavigatorKey.currentState!.push(
        RideStageTransition(
          SelectRide(
            pickupAddress: 'Stockholm Central',
            destinationAddress: 'Arlanda Airport',
            pickupPosition: const LatLng(59.3300, 18.0590),
            destinationPosition: const LatLng(59.6519, 17.9186),
            pickupAlreadyConfirmed: true,
            selection: selection,
            booking: booking,
          ),
          settings: const RouteSettings(name: AppRoutes.selectRide),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.byType(SelectRide), findsOneWidget);

      await tester.tap(find.text('Select Movera'));
      await tester.pump();
      await confirmSetPickup(tester);
      await transport.rideCreateStarted.future;

      final selectRoute = observer.pushed.lastWhere(
        (route) => route.settings.name == AppRoutes.selectRide,
      );
      moveraNavigatorKey.currentState!.removeRoute(selectRoute);
      await tester.pump();
      expect(find.byType(SelectRide), findsNothing);
      expect(find.text('phase55-home'), findsOneWidget);

      transport.allowRideCreate.complete();
      for (
        var i = 0;
        i < 30 && find.byType(FindingDrivers).evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(
        find.byType(FindingDrivers),
        findsOneWidget,
        reason: 'a successful backend ride must get an immediate visible/recovery owner even if Select Ride unmounts',
      );
      final snapshot = await RideSnapshotStore.read();
      expect(snapshot?.rideId, AppScope.instance.ride.rideId);
      expect(snapshot?.status, RideStatus.findingDriver);
      expect(transport.rideCreateCalls, 1);
    },
  );
  test('a Finding owner appearing during create keeps its ride and stands down the duplicate', () async {
    final transport = _GateRideCreateClient();
    final api = ApiClient(client: transport);
    final coordinator = BookingCoordinator(api: api);

    final creating = coordinator.submitFinding(
      pickupAddress: 'Stockholm Central',
      destinationAddress: 'Arlanda Airport',
      pickupLat: 59.3300,
      pickupLng: 18.0590,
      destinationLat: 59.6519,
      destinationLng: 17.9186,
      rideType: 'economy',
      price: 259,
      paymentMethod: 'apple_pay',
      rideTypeLabel: 'Movera',
      paymentMethodLabel: 'Apple Pay',
    );
    await transport.rideCreateStarted.future;

    const existingRideId = 'phase55-existing-finding';
    AppScope.instance.ride
      ..rideId = existingRideId
      ..status = RideStatus.findingDriver
      ..suppressRestore = false
      ..authoritativeVersion = null
      ..authoritativeUpdatedAt = null;

    final realtime = MockRideRealtime(
      assignAfter: const Duration(days: 1),
      api: api,
    );
    final active = FindingDriverController(realtime: realtime, api: api);
    addTearDown(() {
      active.dispose();
      realtime.dispose();
    });
    active.startFrom(
      pickupAddress: 'Existing pickup',
      destinationAddress: 'Existing destination',
      pickupLat: 59.32,
      pickupLng: 18.06,
      destinationLat: 59.34,
      destinationLng: 18.08,
      rideType: 'Movera',
      price: 259,
      paymentMethod: 'Apple Pay',
      onTick: (_) {},
      onMatched: () {},
    );

    expect(FindingDriverController.active, same(active));
    transport.allowRideCreate.complete();
    final resolvedRideId = await creating;

    expect(
      resolvedRideId,
      existingRideId,
      reason: 'the mounted Finding owner remains the authoritative ride',
    );
    expect(AppScope.instance.ride.rideId, existingRideId);
    expect(AppScope.instance.ride.status, RideStatus.findingDriver);

    expect(transport.rides, hasLength(1));
    final duplicate = transport.rides.values.single;
    expect(
      duplicate['status'],
      'cancelled_by_rider',
      reason: 'the newly created race loser must be explicitly stood down, never left searching invisibly',
    );
  });

  testWidgets(
    'rapid double Book creates one authoritative ride and one Finding lifecycle',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final transport = _GateRideCreateClient();
      final api = ApiClient(client: transport);
      final selection = RideSelectionController(
        quotes: ApiQuoteRepository(api: api),
        flags: const FeatureFlags(),
      );
      addTearDown(selection.dispose);
      final booking = BookingController(
        store: BookingRepository(coordinator: BookingCoordinator(api: api)),
      );
      final observer = _RecordingObserver();

      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(375, 812),
          minTextAdapt: true,
          splitScreenMode: true,
          builder: (_, __) => MaterialApp(
            navigatorKey: moveraNavigatorKey,
            navigatorObservers: [observer],
            home: const Scaffold(
              body: Center(child: Text('phase55-double-home')),
            ),
          ),
        ),
      );

      moveraNavigatorKey.currentState!.push(
        RideStageTransition(
          SelectRide(
            pickupAddress: 'Stockholm Central',
            destinationAddress: 'Arlanda Airport',
            pickupPosition: const LatLng(59.3300, 18.0590),
            destinationPosition: const LatLng(59.6519, 17.9186),
            pickupAlreadyConfirmed: true,
            selection: selection,
            booking: booking,
          ),
          settings: const RouteSettings(name: AppRoutes.selectRide),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));

      final book = find.text('Select Movera');
      expect(book, findsOneWidget);

      await tester.tap(book);
      await tester.pump();
      await confirmSetPickup(tester);
      await transport.rideCreateStarted.future;

      // A second physical tap while the first mutation is pending must not
      // create a second backend ride or a second Finding presentation.
      await tester.tap(book);
      await tester.pump();
      expect(transport.rideCreateCalls, 1);

      transport.allowRideCreate.complete();
      for (
        var i = 0;
        i < 30 && find.byType(FindingDrivers).evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.byType(FindingDrivers), findsOneWidget);
      expect(transport.rideCreateCalls, 1);
      expect(transport.rides, hasLength(1));

      final findingPushes = observer.pushed
          .where((route) => route.settings.name == AppRoutes.findingDriver)
          .length;
      expect(findingPushes, 1);

      final onlyRideId = transport.rides.keys.single;
      expect(AppScope.instance.ride.rideId, onlyRideId);
      final snapshot = await RideSnapshotStore.read();
      expect(snapshot?.rideId, onlyRideId);
      expect(snapshot?.status, RideStatus.findingDriver);
    },
  );
}
