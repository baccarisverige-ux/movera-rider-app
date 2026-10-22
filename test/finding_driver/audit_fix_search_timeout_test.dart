import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/router/routes.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/booking/application/booking_controller.dart';
import 'package:movera_rider/features/booking/application/booking_coordinator.dart';
import 'package:movera_rider/features/booking/data/booking_repository.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/data/finding_driver_repository.dart';
import 'package:movera_rider/features/finding_driver/presentation/finding_drivers.dart';
import 'package:movera_rider/features/history/data/on_demand_ride_history_store.dart';
import 'package:movera_rider/features/ride_booking/application/ride_restore_coordinator.dart';
import 'package:movera_rider/features/ride_booking/application/ride_session.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Counts what reaches the in-process backend.
class _Backend extends http.BaseClient {
  _Backend(this.inner);

  final InProcessMockClient inner;
  int cancelPosts = 0;
  int rideGets = 0;
  final List<String?> bookingKeys = <String?>[];

  /// A new booking waits for this before it reaches the backend.
  Completer<void>? holdBooking;

  /// A new booking is lost on the way (no answer: it may exist).
  bool bookingOffline = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (request.method == 'POST' && path.endsWith('/cancel')) cancelPosts += 1;
    if (request.method == 'POST' && path == '/api/v1/rides') {
      bookingKeys.add(request.headers['Idempotency-Key']);
      await holdBooking?.future;
      if (bookingOffline) throw http.ClientException('connection lost');
    }
    if (request.method == 'GET' &&
        RegExp(r'^/api/v1/rides/[^/]+$').hasMatch(path)) {
      rideGets += 1;
    }
    return inner.send(request);
  }
}

RideSnapshot _snapshot(String rideId, {required DateTime searchStartedAt}) =>
    RideSnapshot(
      status: RideStatus.findingDriver,
      savedAt: DateTime.now(),
      searchStartedAt: searchStartedAt,
      pickupAddress: 'A',
      destinationAddress: 'B',
      pickupLat: 59.3,
      pickupLng: 18.0,
      destinationLat: 59.4,
      destinationLng: 18.1,
      rideType: 'Movera',
      price: 259,
      paymentMethod: 'Apple Pay',
      rideId: rideId,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    RideSnapshotStore.epoch = 0;
    FindingDriverController.active = null;
  });

  // Touched from each test body, not setUp: AppScope composes stores whose
  // async work must run on the widget test's clock.
  void resetSession() {
    RideRestoreCoordinator.instance.showing = RestoredSurface.home;
    AppScope.instance.ride
      ..rideId = null
      ..status = RideStatus.idle
      ..suppressRestore = false
      ..authoritativeVersion = null
      ..authoritativeUpdatedAt = null
      ..bookedCategoryId = null
      ..bookedPaymentMethodId = null;
  }

  group('controller', () {
    test('ARCH-3: the 3-minute mark asks the server and keeps the ride '
        'searching; nothing is cancelled locally', () async {
      final server = InProcessMockClient();
      final backend = _Backend(server);
      server.rides['r1'] = {
        'id': 'r1',
        'status': 'findingDriver',
        'version': 1,
      };
      final realtime = MockRideRealtime(assignAfter: const Duration(days: 1));
      addTearDown(realtime.dispose);
      final ride = RideSession()..rideId = 'r1';
      final terminal = <RideStatus>[];
      final controller = FindingDriverController(
        realtime: realtime,
        ride: ride,
        store: FindingDriverRepository(),
        api: ApiClient(client: backend),
        searchTimeout: const Duration(seconds: 5),
      );
      addTearDown(controller.dispose);
      final snapshot = _snapshot('r1', searchStartedAt: DateTime.now());
      await RideSnapshotStore.save(snapshot);
      controller.start(
        snapshot: snapshot,
        onTick: (_) {},
        onMatched: () {},
        onTerminal: terminal.add,
      );
      controller.debugAdvance(5);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(controller.stillLooking, isTrue);
      expect(controller.showStillLooking, isTrue);
      expect(controller.copy.headline, 'Still looking for a driver');
      expect(backend.rideGets, greaterThanOrEqualTo(1));
      expect(backend.cancelPosts, 0);
      expect(terminal, isEmpty);
      expect(ride.status.isTerminal, isFalse);
      expect((await RideSnapshotStore.read())?.rideId, 'r1');

      controller.keepSearching();
      expect(controller.showStillLooking, isFalse);
      expect(controller.stillLooking, isTrue);
    });

    test('ARCH-3 / RIDE-5: the mark survives a reload (measured from the '
        'search start, not the mount)', () async {
      final server = InProcessMockClient();
      server.rides['r2'] = {
        'id': 'r2',
        'status': 'findingDriver',
        'version': 1,
      };
      final realtime = MockRideRealtime(assignAfter: const Duration(days: 1));
      addTearDown(realtime.dispose);
      final controller = FindingDriverController(
        realtime: realtime,
        ride: RideSession()..rideId = 'r2',
        store: FindingDriverRepository(),
        api: ApiClient(client: server),
      );
      addTearDown(controller.dispose);
      controller.start(
        snapshot: _snapshot(
          'r2',
          searchStartedAt: DateTime.now().subtract(const Duration(minutes: 4)),
        ),
        onTick: (_) {},
        onMatched: () {},
      );
      expect(controller.elapsedSeconds, greaterThanOrEqualTo(240));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(controller.stillLooking, isTrue);
    });

    test('RIDE-5: a search the server ended is archived to History', () async {
      final server = InProcessMockClient();
      server.rides['r3'] = {
        'id': 'r3',
        'status': 'noDriverFound',
        'version': 3,
      };
      final realtime = MockRideRealtime(assignAfter: const Duration(days: 1));
      addTearDown(realtime.dispose);
      final ride = RideSession()..rideId = 'r3';
      final terminal = <RideStatus>[];
      final controller = FindingDriverController(
        realtime: realtime,
        ride: ride,
        store: FindingDriverRepository(),
        api: ApiClient(client: server),
      );
      addTearDown(controller.dispose);
      final snapshot = _snapshot(
        'r3',
        searchStartedAt: DateTime.now().subtract(const Duration(minutes: 5)),
      );
      await RideSnapshotStore.save(snapshot);
      controller.start(
        snapshot: snapshot,
        onTick: (_) {},
        onMatched: () {},
        onTerminal: terminal.add,
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(terminal, <RideStatus>[RideStatus.noDriverFound]);
      expect(ride.status, RideStatus.noDriverFound);
      expect(await RideSnapshotStore.read(), isNull);
      final history = await OnDemandRideHistoryStore.read();
      expect(history.single.reservationId, 'ondemand-r3');
      expect(history.single.status.name, 'cancelled');
    });

    test('in-process mock expires a search nobody accepted', () async {
      final server = InProcessMockClient(searchExpiresAfter: Duration.zero);
      final api = ApiClient(client: server);
      final id = await BookingCoordinator(api: api).submitFinding(
        pickupAddress: 'A',
        destinationAddress: 'B',
        pickupLat: 59.3,
        pickupLng: 18.0,
        destinationLat: 59.4,
        destinationLng: 18.1,
        rideType: 'economy',
        price: 259,
        paymentMethod: 'visa',
      );
      final json = await api.get('/api/v1/rides/$id');
      expect((json['ride'] as Map)['status'], 'expired');
      expect((json['ride'] as Map)['version'], 2);
    });
  });

  group('screen', () {
    late InProcessMockClient server;
    late _Backend backend;
    late ApiClient api;
    late MockRideRealtime realtime;
    late BookingCoordinator coordinator;

    Future<void> pumpUntil(
      WidgetTester tester,
      bool Function() done, {
      int max = 80,
    }) async {
      for (var i = 0; i < max && !done(); i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    /// A ride the server is searching for, owned by the session as a
    /// booking would leave it.
    String seedRide(String id) {
      resetSession();
      server.rides[id] = {
        'id': id,
        'status': 'findingDriver',
        'version': 1,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
        'searchStartedAt': DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 4))
            .toIso8601String(),
        'categoryId': 'economy',
        'paymentMethodId': 'visa',
      };
      AppScope.instance.ride
        ..rideId = id
        ..status = RideStatus.findingDriver
        ..authoritativeVersion = 1
        ..bookedCategoryId = 'economy'
        ..bookedPaymentMethodId = 'visa';
      return id;
    }

    Future<FindingDriverController> openFinding(
      WidgetTester tester, {
      required DateTime searchStartedAt,
    }) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = FindingDriverController(realtime: realtime, api: api);
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(375, 812),
          minTextAdapt: true,
          splitScreenMode: true,
          builder: (_, __) => MaterialApp(
            navigatorKey: nav,
            home: const Scaffold(body: Center(child: Text('timeout-home'))),
          ),
        ),
      );
      nav.currentState!.push(
        RideStageTransition(
          FindingDrivers(
            pickupAddress: 'Stockholm Central',
            destinationAddress: 'Arlanda Airport',
            pickupPosition: const LatLng(59.33, 18.059),
            destinationPosition: const LatLng(59.6519, 17.9186),
            rideType: 'Movera',
            price: 349,
            paymentMethod: 'Apple Pay',
            realtime: realtime,
            searchStartedAt: searchStartedAt,
            controller: controller,
            booking: BookingController(
              store: BookingRepository(coordinator: coordinator),
            ),
          ),
          settings: const RouteSettings(name: AppRoutes.findingDriver),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      return controller;
    }

    tearDown(() => realtime.dispose());

    void setUpBackend({Duration expiry = const Duration(hours: 1)}) {
      server = InProcessMockClient(searchExpiresAfter: expiry);
      backend = _Backend(server);
      api = ApiClient(client: backend);
      realtime = MockRideRealtime(
        assignAfter: const Duration(days: 1),
        api: api,
      );
      coordinator = BookingCoordinator(api: api);
    }

    testWidgets('ARCH-3: "Still looking" offers Keep searching and Cancel '
        'request while the server keeps searching', (tester) async {
      setUpBackend();
      final rideId = seedRide('to-still-looking');
      await openFinding(
        tester,
        searchStartedAt: DateTime.now().subtract(const Duration(minutes: 4)),
      );
      await pumpUntil(
        tester,
        () => find.text('Keep searching').evaluate().isNotEmpty,
      );

      expect(find.text('Still looking for a driver'), findsWidgets);
      expect(find.text('Keep searching'), findsOneWidget);
      expect(find.byType(FindingDrivers), findsOneWidget);
      expect(backend.rideGets, greaterThanOrEqualTo(1));
      expect(backend.cancelPosts, 0);
      expect(AppScope.instance.ride.status.isTerminal, isFalse);
      expect(server.rides[rideId]!['status'], 'findingDriver');

      // Cancel request goes through the normal (server-first) cancel sheet.
      await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel request'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Cancel ride?'), findsOneWidget);
      // The sheet's own "Keep searching" closes it without cancelling.
      await tester.tap(find.text('Keep searching').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Cancel ride?'), findsNothing);

      await tester.tap(find.text('Keep searching'));
      await tester.pump();
      expect(find.text('Keep searching'), findsNothing);
      expect(find.byType(FindingDrivers), findsOneWidget);
      expect(backend.cancelPosts, 0);
    });

    /// Opens a search for [id] that the server ends with no driver found.
    Future<FindingDriverController> noDriverFound(
      WidgetTester tester,
      String id,
    ) async {
      setUpBackend(expiry: Duration.zero);
      seedRide(id);
      final controller = await openFinding(
        tester,
        searchStartedAt: DateTime.now(),
      );
      // The periodic check, driven from the test so its storage work runs
      // on the test's clock.
      unawaited(controller.checkServerSearchState());
      await pumpUntil(
        tester,
        () => find.text('No driver found').evaluate().isNotEmpty,
      );
      await tester.pump(const Duration(milliseconds: 400));
      return controller;
    }

    /// Waits until [controller] searches for a new ride, not [firstId].
    Future<void> searchingAgain(
      WidgetTester tester,
      FindingDriverController controller,
      String firstId,
    ) async {
      await pumpUntil(
        tester,
        () =>
            AppScope.instance.ride.rideId != firstId &&
            controller.ownedRideId == AppScope.instance.ride.rideId,
      );
      await tester.pump(const Duration(milliseconds: 400));
    }

    /// rider-u107: Try again prices the route again; the fare differs from
    /// the 349 kr this search showed, so the rider is asked first.
    Future<void> tryAgainAtNewPrice(WidgetTester tester) async {
      await tester.tap(find.text('Try again'));
      final accept = find.byKey(const ValueKey('rebook-price-accept'));
      await pumpUntil(tester, () => accept.evaluate().isNotEmpty);
      expect(find.text('Price updated'), findsOneWidget);
      await tester.tap(accept);
      await tester.pump();
    }

    testWidgets('RIDE-19: after the server says no driver, Try again '
        'requests the same ride as a new booking', (tester) async {
      const firstId = 'to-try-again';
      final controller = await noDriverFound(tester, firstId);
      expect(find.text('No driver found'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Change route'), findsOneWidget);
      expect(AppScope.instance.ride.status, RideStatus.noDriverFound);
      final history = await OnDemandRideHistoryStore.read();
      expect(history.single.reservationId, 'ondemand-$firstId');

      // The next booking should not expire straight away.
      server.rides.clear();
      await tryAgainAtNewPrice(tester);
      await searchingAgain(tester, controller, firstId);

      final secondId = AppScope.instance.ride.rideId;
      expect(secondId, isNotNull);
      expect(secondId, isNot(firstId));
      expect(server.rides[secondId]!['categoryId'], 'economy');
      expect(server.rides[secondId]!['paymentMethodId'], 'visa');
      expect(server.rides[secondId]!['destinationAddress'], 'Arlanda Airport');
      // One new booking, with its own idempotency key.
      expect(backend.bookingKeys, hasLength(1));
      expect(backend.bookingKeys.single, isNotNull);
      expect(find.byType(FindingDrivers), findsOneWidget);
      expect(find.text('No driver found'), findsNothing);
      expect(controller.stillLooking, isFalse);
      expect(AppScope.instance.ride.status, RideStatus.findingDriver);
    });

    testWidgets('RIDE-19: Change route goes back to Home', (tester) async {
      await noDriverFound(tester, 'to-change-route');
      await tester.tap(find.text('Change route'));
      await pumpUntil(
        tester,
        () => find.byType(FindingDrivers).evaluate().isEmpty,
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('timeout-home'), findsOneWidget);
      expect(backend.bookingKeys, isEmpty);
      expect(AppScope.instance.ride.status, RideStatus.noDriverFound);
    });

    testWidgets('rider-u107: Try again at a changed price books nothing '
        'until the rider accepts it', (tester) async {
      await noDriverFound(tester, 'to-new-price');
      server.rides.clear();
      await tester.tap(find.text('Try again'));
      final notNow = find.text('Not now');
      await pumpUntil(tester, () => notNow.evaluate().isNotEmpty);
      expect(find.text('Price updated'), findsOneWidget);

      await tester.tap(notNow);
      await pumpUntil(
        tester,
        () => find.text('No driver found').evaluate().isNotEmpty,
      );
      expect(backend.bookingKeys, isEmpty, reason: 'nothing was booked');
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('rider-u106: back while Try again books keeps the screen, '
        'which then owns the new search', (tester) async {
      const firstId = 'to-back-while-booking';
      final controller = await noDriverFound(tester, firstId);
      server.rides.clear();
      backend.holdBooking = Completer<void>();
      await tryAgainAtNewPrice(tester);
      await pumpUntil(tester, () => backend.bookingKeys.isNotEmpty);
      await tester.pump();

      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(FindingDrivers), findsOneWidget);

      backend.holdBooking!.complete();
      await searchingAgain(tester, controller, firstId);
      expect(find.byType(FindingDrivers), findsOneWidget);
      expect(controller.ownedRideId, isNot(firstId));
    });

    testWidgets('rider-u108: a Try again that may have booked stays on the '
        'screen and retries the same booking', (tester) async {
      const firstId = 'to-maybe-booked';
      final controller = await noDriverFound(tester, firstId);
      server.rides.clear();
      backend.bookingOffline = true;
      await tryAgainAtNewPrice(tester);
      final uncertain = find.text(
        'We couldn’t confirm your booking. Check your connection and try '
        'again.',
      );
      await pumpUntil(
        tester,
        () =>
            uncertain.evaluate().isNotEmpty ||
            find.text('timeout-home').evaluate().isNotEmpty,
        max: 200,
      );
      await tester.pump(const Duration(milliseconds: 400));

      expect(uncertain, findsOneWidget);
      expect(find.text('timeout-home'), findsNothing);
      expect(find.byType(FindingDrivers), findsOneWidget);

      backend.bookingOffline = false;
      await tester.tap(find.text('Try again'));
      await searchingAgain(tester, controller, firstId);
      expect(find.byType(FindingDrivers), findsOneWidget);
      // Every send was the same booking: one key, so at most one ride.
      expect(backend.bookingKeys.toSet(), hasLength(1));
    });
  });
}
