import 'dart:async';

import 'package:movera_rider/features/pickup/presentation/set_pickup_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/app/router/routes.dart';
import 'package:movera_rider/app/router/home_history_observer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:movera_rider/features/ride_complete/presentation/ride_completed.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/history/data/on_demand_ride_history_store.dart';
import 'package:movera_rider/features/finding_driver/presentation/finding_drivers.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/active_ride/presentation/driver_cancelled_notice.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/app/navigator_key.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/features/ride_booking/data/api_quote_repository.dart';
import 'package:movera_rider/features/booking/data/booking_repository.dart';
import 'package:movera_rider/features/booking/application/booking_coordinator.dart';
import 'package:movera_rider/features/booking/application/booking_controller.dart';
import 'package:movera_rider/core/feature_flags/feature_flags.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/features/reservations/presentation/ride_scheduled.dart';
import 'package:movera_rider/features/pickup/presentation/confirm_pickup_spot.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/presentation/upcoming_reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/quote.dart';
import 'package:movera_rider/features/ride_booking/data/mock_quote_repository.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';

class _RecordingObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushed = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute != null) pushed.add(newRoute);
  }
}

class _NeverQuotes implements QuoteRepository {
  int calls = 0;

  @override
  Future<RideQuote> quote({
    required String rideType,
    required int distanceMeters,
    int durationSeconds = 600,
    String? pickup,
    String? destination,
    GeoPoint? pickupPoint,
    GeoPoint? destinationPoint,
    List<RouteStop> stops = const <RouteStop>[],
  }) {
    calls += 1;
    return Completer<RideQuote>().future;
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
      ..status = RideStatus.idle;
  });

  testWidgets('Select Ride transition carries its stable route name', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final navigatorKey = GlobalKey<NavigatorState>();
    final observer = _RecordingObserver();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [observer],
        home: const Scaffold(body: Text('phase54-home')),
      ),
    );

    navigatorKey.currentState!.push(
      RideStageTransition(
        const SelectRide(
          pickupAddress: 'Stockholm Central',
          destinationAddress: 'Arlanda Airport',
          pickupPosition: LatLng(59.3300, 18.0590),
          destinationPosition: LatLng(59.6519, 17.9186),
        ),
        settings: const RouteSettings(name: AppRoutes.selectRide),
      ),
    );
    await tester.pump();

    expect(observer.pushed.last.settings.name, AppRoutes.selectRide);
  });
  testWidgets(
    'Ride Scheduled Done returns to named Home instead of assuming first route',
    (tester) async {
      final controller = ReservationController(
        store: LocalReservationRepository(
          storage: MemoryReservationStorage(),
          nextId: () => 'phase54-scheduled-home',
        ),
      );
      final created = await controller.create(
        ReservationDraft(
          scheduledPickupAt: DateTime(2026, 9, 24, 18),
          pickup: const ReservationPlace(
            label: 'Stockholm Central',
            lat: 59.3300,
            lng: 18.0590,
          ),
          destination: const ReservationPlace(
            label: 'Arlanda Airport',
            lat: 59.6519,
            lng: 17.9186,
          ),
          categoryId: 'economy',
          categoryName: 'Movera',
          categoryImage: 'assets/images/rides/movera.webp',
          price: 349,
          paymentMethod: 'Apple Pay',
        ),
      );

      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: const Scaffold(body: Text('phase54-shell')),
        ),
      );

      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: AppRoutes.home),
          builder: (_) => const Scaffold(body: Text('phase54-home')),
        ),
      );
      navigatorKey.currentState!.push(
        BottomToTopTransition<void>(
          RideScheduledPage(
            reservationId: created.reservationId,
            controller: controller,
          ),
          settings: const RouteSettings(name: AppRoutes.reservationScheduled),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Your ride is scheduled'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(find.text('phase54-home'), findsOneWidget);
      expect(find.text('phase54-shell'), findsNothing);
    },
  );

  test(
    'Select Ride quote cancellation releases an in-flight quote batch',
    () async {
      final quotes = _NeverQuotes();
      final selection = RideSelectionController(quotes: quotes);
      final generation = selection.beginQuotes();

      final pending = selection.loadQuotes(
        generation: generation,
        pickup: 'Stockholm Central',
        destination: 'Arlanda Airport',
        parallelism: 1,
        timeout: const Duration(minutes: 5),
      );

      await Future<void>.delayed(Duration.zero);
      expect(quotes.calls, 1);
      expect(selection.hasPendingQuoteRequests, isTrue);

      selection.cancelPendingQuotes();
      await pending.timeout(const Duration(seconds: 1));

      expect(selection.hasPendingQuoteRequests, isFalse);
      selection.dispose();
    },
  );

  testWidgets('Back from Select Ride returns cleanly with no route exception', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: Text('phase54-select-parent')),
      ),
    );

    navigatorKey.currentState!.push(
      RideStageTransition(
        const SelectRide(
          pickupAddress: 'Stockholm Central',
          destinationAddress: 'Arlanda Airport',
          pickupPosition: LatLng(59.3300, 18.0590),
          destinationPosition: LatLng(59.6519, 17.9186),
        ),
        settings: const RouteSettings(name: AppRoutes.selectRide),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));

    expect(find.byType(SelectRide), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.text('phase54-select-parent'), findsOneWidget);
    expect(find.byType(SelectRide), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Confirm pickup carries the on-demand journey route identity', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final navigatorKey = GlobalKey<NavigatorState>();
    final observer = _RecordingObserver();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [observer],
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                ConfirmPickupSpot.open(
                  context,
                  initialPosition: const LatLng(59.3300, 18.0590),
                  initialAddress: 'Stockholm Central',
                );
              },
              child: const Text('open-confirm-pickup'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open-confirm-pickup'));
    await tester.pump();
    expect(observer.pushed.last.settings.name, AppRoutes.confirmPickup);
  });

  testWidgets(
    'on-demand journey keeps one visible ride stage and returns Home after feedback',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final observer = _RecordingObserver();
      final transport = InProcessMockClient();
      final api = ApiClient(client: transport);
      final selection = RideSelectionController(
        quotes: ApiQuoteRepository(api: api),
        flags: const FeatureFlags(),
      );
      final booking = BookingController(
        store: BookingRepository(coordinator: BookingCoordinator(api: api)),
      );
      final realtime = MockRideRealtime(
        assignAfter: const Duration(days: 1),
        boardAfter: const Duration(seconds: 2),
        tripTick: const Duration(milliseconds: 40),
        tripTicks: 2,
        paymentProcessingAfter: const Duration(milliseconds: 40),
        paymentFinalizedAfter: const Duration(milliseconds: 40),
        ratingPendingAfter: const Duration(milliseconds: 40),
        api: api,
      );
      addTearDown(realtime.dispose);
      addTearDown(selection.dispose);

      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(375, 812),
          minTextAdapt: true,
          splitScreenMode: true,
          builder: (_, __) {
            return MaterialApp(
              navigatorKey: moveraNavigatorKey,
              navigatorObservers: [observer],
              home: Builder(
                builder: (homeContext) => Scaffold(
                  body: Center(
                    child: TextButton(
                      onPressed: () async {
                        final pickup = await ConfirmPickupSpot.open(
                          homeContext,
                          initialPosition: const LatLng(59.3300, 18.0590),
                          initialAddress: 'Stockholm Central',
                        );
                        if (pickup == null || !homeContext.mounted) return;
                        await Navigator.of(homeContext).push<void>(
                          RideStageTransition(
                            SelectRide(
                              pickupAddress: pickup.address,
                              destinationAddress: 'Arlanda Airport',
                              pickupPosition: pickup.position,
                              destinationPosition: const LatLng(
                                59.6519,
                                17.9186,
                              ),
                              selection: selection,
                              booking: booking,
                              realtime: realtime,
                            ),
                            settings: const RouteSettings(
                              name: AppRoutes.selectRide,
                            ),
                          ),
                        );
                      },
                      child: const Text('phase54-start-on-demand'),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );

      await tester.tap(find.text('phase54-start-on-demand'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(ConfirmPickupSpot), findsOneWidget);
      expect(observer.pushed.last.settings.name, AppRoutes.confirmPickup);

      await tester.tap(find.widgetWithText(FilledButton, 'Confirm pickup'));
      await tester.pump();
      for (
        var i = 0;
        i < 20 && find.byType(SelectRide).evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(SelectRide), findsOneWidget);
      expect(observer.pushed.last.settings.name, AppRoutes.selectRide);

      // Allow the authoritative quote batch to settle before booking.
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Select Movera'));
      await tester.pump();
      // Book now opens Set pickup; confirming it starts the search.
      for (
        var i = 0;
        i < 30 && find.byType(SetPickupPage).evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(SetPickupPage), findsOneWidget);
      expect(observer.pushed.last.settings.name, AppRoutes.confirmPickup);
      // P5-R6: Set pickup finishes opening before the rider confirms (a tap
      // while it slides in is the second tap of a double tap and is ignored).
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Confirm and search'));
      await tester.pump();
      for (
        var i = 0;
        i < 30 && find.byType(FindingDrivers).evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.byType(FindingDrivers), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 160));
      expect(find.byType(SelectRide), findsNothing);
      expect(observer.pushed.last.settings.name, AppRoutes.findingDriver);
      final rideId = AppScope.instance.ride.rideId;
      expect(rideId, isNotNull);
      expect(AppScope.instance.ride.status, RideStatus.findingDriver);

      realtime.assignNow();
      await tester.pump();
      for (
        var i = 0;
        i < 30 && find.byType(WaitingForDriver).evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.byType(WaitingForDriver), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 160));
      expect(find.byType(FindingDrivers), findsNothing);
      expect(observer.pushed.last.settings.name, AppRoutes.waitingForDriver);
      expect(AppScope.instance.ride.rideId, rideId);

      // Drive the real mock lifecycle through pickup, trip, payment and rating.
      // Arrival intentionally opens a root modal route. Certify that handoff
      // without coupling this lifecycle test to smooth_sheets' visual offset.
      final routesBeforeArrival = observer.pushed.length;
      realtime.markArrivedForTest();
      await tester.pump();
      for (
        var i = 0;
        i < 25 && observer.pushed.length == routesBeforeArrival;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(observer.pushed.length, greaterThan(routesBeforeArrival));
      expect(observer.pushed.last.settings.name, isNull);

      // Close exactly the arrival child route, then let the live ride resume.
      moveraNavigatorKey.currentState!.pop();
      await tester.pump(const Duration(milliseconds: 400));
      for (
        var i = 0;
        i < 35 && find.byType(RideCompleted).evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(RideCompleted), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 160));
      expect(find.byType(WaitingForDriver), findsNothing);
      expect(observer.pushed.last.settings.name, AppRoutes.rideCompleted);
      expect(AppScope.instance.ride.rideId, rideId);

      // Completion opens at tripCompleted. Post-trip statuses are backend
      // authored and each one schedules the next timer only after it fires, so
      // advance in small steps until the real transport reaches ratingPending
      // instead of assuming one fixed delay can flush the entire chain.
      for (
        var i = 0;
        i < 30 && realtime.lastStatus != RideStatus.ratingPending;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(realtime.lastStatus, RideStatus.ratingPending);
      await tester.pump();

      final feedbackLock = tester.widget<IgnorePointer>(
        find.byKey(const ValueKey('completion-feedback-lock')),
      );
      expect(feedbackLock.ignoring, isFalse);

      await tester.tap(
        find.byKey(const ValueKey<String>('ride-completed-done')),
      );
      await tester.pumpAndSettle();

      expect(find.text('phase54-start-on-demand'), findsOneWidget);
      expect(find.byType(SelectRide), findsNothing);
      expect(find.byType(FindingDrivers), findsNothing);
      expect(find.byType(WaitingForDriver), findsNothing);
      expect(find.byType(RideCompleted), findsNothing);
      expect(AppScope.instance.ride.status, RideStatus.closed);

      final lifecycleNames = observer.pushed
          .map((route) => route.settings.name)
          .whereType<String>()
          .where(
            (name) => <String>{
              AppRoutes.confirmPickup,
              AppRoutes.selectRide,
              AppRoutes.findingDriver,
              AppRoutes.waitingForDriver,
              AppRoutes.rideCompleted,
            }.contains(name),
          )
          .toList();
      expect(
        lifecycleNames,
        containsAllInOrder(<String>[
          AppRoutes.confirmPickup,
          AppRoutes.selectRide,
          AppRoutes.findingDriver,
          AppRoutes.waitingForDriver,
          AppRoutes.rideCompleted,
        ]),
      );
    },
  );

  testWidgets(
    'scheduled journey preserves reservation identity through live ride, feedback, and Home',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = ReservationController(
        store: LocalReservationRepository(
          storage: MemoryReservationStorage(),
          nextId: () => 'phase54-scheduled-flow',
        ),
      );
      final created = await controller.create(
        ReservationDraft(
          scheduledPickupAt: DateTime(2026, 9, 24, 18),
          pickup: const ReservationPlace(
            label: 'Stockholm Central',
            lat: 59.3300,
            lng: 18.0590,
          ),
          destination: const ReservationPlace(
            label: 'Arlanda Airport',
            lat: 59.6519,
            lng: 17.9186,
          ),
          categoryId: 'economy',
          categoryName: 'Movera',
          categoryImage: 'assets/images/rides/movera.webp',
          price: 349,
          paymentMethod: 'Apple Pay',
        ),
      );
      await controller.update(
        created.reservationId,
        const ReservationPatch(
          status: ReservationStatus.driverAssignmentPending,
        ),
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
              body: Center(child: Text('phase54-scheduled-home')),
            ),
          ),
        ),
      );

      moveraNavigatorKey.currentState!.push(
        RightToLeftTransition(
          UpcomingReservationPage(
            reservationId: created.reservationId,
            controller: controller,
          ),
          settings: const RouteSettings(name: AppRoutes.reservationUpcoming),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(UpcomingReservationPage), findsOneWidget);
      expect(observer.pushed.last.settings.name, AppRoutes.reservationUpcoming);
      expect(
        controller.byId(created.reservationId)?.status,
        ReservationStatus.driverAssignmentPending,
      );

      const driver = ReservationDriver(
        firstName: 'Amina',
        rating: 4.9,
        vehicle: 'Volvo EX40',
        plate: 'ABC 123',
      );
      await controller.assignMockDriver(created.reservationId, driver: driver);
      await tester.pump();
      expect(find.byType(UpcomingReservationPage), findsOneWidget);

      await controller.update(
        created.reservationId,
        const ReservationPatch(status: ReservationStatus.driverEnRoute),
      );
      for (
        var i = 0;
        i < 20 && find.byType(WaitingForDriver).evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.byType(WaitingForDriver), findsOneWidget);
      expect(observer.pushed.last.settings.name, AppRoutes.reservationLive);
      final live = tester.widget<WaitingForDriver>(
        find.byType(WaitingForDriver),
      );
      expect(live.rideId, created.reservationId);
      expect(live.persistRideSnapshot, isFalse);

      await controller.update(
        created.reservationId,
        const ReservationPatch(status: ReservationStatus.inProgress),
      );
      await tester.pump();
      expect(
        controller.byId(created.reservationId)?.status,
        ReservationStatus.inProgress,
      );
      expect(find.byType(WaitingForDriver), findsOneWidget);

      await controller.update(
        created.reservationId,
        const ReservationPatch(status: ReservationStatus.completed),
      );
      for (
        var i = 0;
        i < 20 && find.byType(RideCompleted).evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.byType(RideCompleted), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 160));
      expect(find.byType(WaitingForDriver), findsNothing);
      expect(observer.pushed.last.settings.name, AppRoutes.rideCompleted);
      final completed = tester.widget<RideCompleted>(
        find.byType(RideCompleted),
      );
      expect(completed.rideId, created.reservationId);
      expect(completed.persistOnDemandState, isFalse);

      expect(
        find.byKey(const ValueKey('completion-feedback-lock')),
        findsOneWidget,
      );
      final feedbackLock = tester.widget<IgnorePointer>(
        find.byKey(const ValueKey('completion-feedback-lock')),
      );
      expect(feedbackLock.ignoring, isFalse);

      await tester.tap(
        find.byKey(const ValueKey<String>('ride-completed-done')),
      );
      await tester.pumpAndSettle();

      expect(find.text('phase54-scheduled-home'), findsOneWidget);
      expect(find.byType(UpcomingReservationPage), findsNothing);
      expect(find.byType(WaitingForDriver), findsNothing);
      expect(find.byType(RideCompleted), findsNothing);
      expect(
        controller.byId(created.reservationId)?.reservationId,
        created.reservationId,
      );
    },
  );

  testWidgets(
    'driver cancellation returns Waiting to the existing Finding route without duplicating stages',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const rideId = 'phase54-driver-cancel-research';
      AppScope.instance.ride
        ..rideId = rideId
        ..status = RideStatus.findingDriver
        ..suppressRestore = false
        ..authoritativeVersion = null
        ..authoritativeUpdatedAt = null;

      final realtime = MockRideRealtime(assignAfter: const Duration(days: 1));
      addTearDown(realtime.dispose);

      final observer = _RecordingObserver();
      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(375, 812),
          minTextAdapt: true,
          splitScreenMode: true,
          builder: (_, __) => MaterialApp(
            navigatorKey: navigatorKey,
            navigatorObservers: [observer, HomeHistoryObserver()],
            home: const Scaffold(
              body: Center(child: Text('phase54-driver-cancel-home')),
            ),
          ),
        ),
      );

      navigatorKey.currentState!.push(
        RideStageTransition(
          FindingDrivers(
            pickupAddress: 'Stockholm Central',
            destinationAddress: 'Arlanda Airport',
            pickupPosition: const LatLng(59.3300, 18.0590),
            destinationPosition: const LatLng(59.6519, 17.9186),
            rideType: 'Movera',
            price: 349,
            paymentMethod: 'Apple Pay',
            realtime: realtime,
          ),
          settings: const RouteSettings(name: AppRoutes.findingDriver),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(FindingDrivers), findsOneWidget);
      expect(observer.pushed.last.settings.name, AppRoutes.findingDriver);

      realtime.assignNow();
      for (
        var i = 0;
        i < 30 && find.byType(WaitingForDriver).evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.byType(WaitingForDriver), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byType(FindingDrivers), findsNothing);
      expect(observer.pushed.last.settings.name, AppRoutes.waitingForDriver);
      expect(AppScope.instance.ride.rideId, rideId);

      // Model the production contract: Waiting reacts to the authoritative
      // cancelledByDriver realtime event. The mock helper's internal timer
      // bookkeeping is not part of the navigation contract under test.
      realtime.emit(RideStatus.cancelledByDriver);
      await tester.pump();

      for (
        var i = 0;
        i < 20 && find.byType(DriverCancelledNotice).evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // No question for the rider: a notice explains, and the search is
      // already back without any tap.
      expect(realtime.lastStatus, RideStatus.findingDriver);
      expect(find.byType(DriverCancelledNotice), findsWidgets);
      expect(find.text('Keep searching'), findsNothing);
      for (
        var i = 0;
        i < 30 && find.byType(FindingDrivers).evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump(const Duration(milliseconds: 160));

      expect(find.byType(WaitingForDriver), findsNothing);
      expect(find.byType(FindingDrivers), findsOneWidget);
      expect(find.text('phase54-driver-cancel-home'), findsNothing);
      expect(AppScope.instance.ride.rideId, rideId);
      expect(AppScope.instance.ride.status, RideStatus.findingDriver);
      expect(realtime.lastStatus, RideStatus.findingDriver);

      final findingPushes = observer.pushed
          .where((route) => route.settings.name == AppRoutes.findingDriver)
          .length;
      final waitingPushes = observer.pushed
          .where((route) => route.settings.name == AppRoutes.waitingForDriver)
          .length;
      expect(findingPushes, 1);
      expect(waitingPushes, 1);

      final stored = await RideSnapshotStore.read();
      expect(stored?.rideId, rideId);
      expect(await OnDemandRideHistoryStore.read(), isEmpty);

      realtime.holdAssignment();
      navigatorKey.currentState!.popUntil((route) => route.isFirst);
      await tester.pump(driverCancelledNoticeDuration);
      await tester.pumpAndSettle();
    },
  );
}
