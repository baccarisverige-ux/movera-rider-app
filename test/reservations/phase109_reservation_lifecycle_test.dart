import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/router/routes.dart';
import 'package:movera_rider/core/observability/observability.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/data/mock_reservation_dispatch.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_errors.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';
import 'package:movera_rider/features/reservations/presentation/home_reservation_chrono.dart';
import 'package:movera_rider/features/ride_complete/presentation/ride_completed.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Phase 111: the chrono ring is neutral unless no driver was found; the
// state is carried by the corner badge.
const _neutralRing = Color(0x55172127);

/// Batch 10 Phase 109 — a scheduled ride actually lives through its lifecycle
/// in mock builds (demo/dev/test), reveals the driver at the right time, and
/// never re-opens once finished.
///
/// These tests use the real composition root (`AppScope.composeForEnvironment`)
/// so they exercise exactly what `di.dart` wires per flavor, and they only use
/// APIs that already existed before Phase 109 — so they run (and fail) on the
/// base commit as well. Behavioural only: no source reads.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const demo = AppEnv(
    flavor: AppFlavor.demo,
    apiBaseUrl: 'https://api.demo.movera.invalid',
  );
  const staging = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://api.staging.movera.example',
  );

  // Fixed wall-clock for the reservation; the chrono's clock is a fake that
  // each test moves by hand.
  final pickupAt = DateTime(2026, 10, 1, 12);

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(Observability.reset);

  Future<Reservation> schedule(ReservationController c) async {
    await c.hydrate();
    return c.create(
      ReservationDraft(
        scheduledPickupAt: pickupAt,
        pickup: const ReservationPlace(
          label: 'Stockholm Central',
          lat: 59.3293,
          lng: 18.0686,
        ),
        destination: const ReservationPlace(
          label: 'Arlanda Airport',
          lat: 59.6519,
          lng: 17.9186,
        ),
        categoryId: 'economy',
        categoryName: 'Movera',
        categoryImage: 'assets/images/rides/movera.webp',
        price: 459,
        paymentMethod: 'Visa •••• 4242',
      ),
    );
  }

  // ARCH-7: a staging/production composition has no server reservations
  // yet, so Book for later is off there and nothing is booked on the device.
  test(
    'staging composition refuses to book for later on this device',
    () async {
      final scope = AppScope.composeForEnvironment(staging);
      addTearDown(scope.disposeForTest);
      await expectLater(
        schedule(scope.reservations),
        throwsA(isA<ReservationsUnavailableException>()),
      );
      expect(scope.reservations.all, isEmpty);
    },
  );

  test('staging environment: never assigns, times out into No driver found '
      'exactly as before', () async {
    // The dispatch gate itself, with a repository that can store the ride:
    // a non-mock environment ignores even an injected mock dispatcher.
    final c = ReservationController(
      store: LocalReservationRepository(storage: MemoryReservationStorage()),
      environment: staging,
      mockDispatch: MockReservationDispatch(),
    );
    addTearDown(c.dispose);
    final ride = await schedule(c);
    final id = ride.reservationId;

    await c.startLiveIfDue(now: pickupAt.subtract(const Duration(minutes: 30)));
    expect(c.byId(id)!.status, ReservationStatus.scheduled);
    expect(c.byId(id)!.driver, isNull);

    await c.startLiveIfDue(now: pickupAt.subtract(const Duration(minutes: 2)));
    expect(c.byId(id)!.status, ReservationStatus.driverAssignmentPending);
    expect(c.byId(id)!.driver, isNull);

    final late = pickupAt.add(ReservationController.noDriverFoundAfter);
    await c.startLiveIfDue(now: late);
    expect(c.byId(id)!.status, ReservationStatus.driverAssignmentPending);
    expect(c.isNoDriverFound(c.byId(id)!, now: late), isTrue);
  });

  test('demo composition assigns a mock driver at T-30 min and flips to en '
      'route at T-2 min', () async {
    final scope = AppScope.composeForEnvironment(demo);
    addTearDown(scope.disposeForTest);
    final c = scope.reservations;
    final ride = await schedule(c);
    final id = ride.reservationId;

    await c.startLiveIfDue(now: pickupAt.subtract(const Duration(minutes: 31)));
    expect(c.byId(id)!.status, ReservationStatus.scheduled);
    expect(c.byId(id)!.driver, isNull);

    await c.startLiveIfDue(now: pickupAt.subtract(const Duration(minutes: 30)));
    expect(c.byId(id)!.status, ReservationStatus.driverAssigned);
    expect(c.byId(id)!.driver?.firstName, isIn(['Elin', 'Johan', 'Amina']));
    expect(c.byId(id)!.revealsDriver, isFalse);

    await c.startLiveIfDue(now: pickupAt.subtract(const Duration(minutes: 3)));
    expect(c.byId(id)!.status, ReservationStatus.driverAssigned);

    await c.startLiveIfDue(now: pickupAt.subtract(const Duration(minutes: 2)));
    expect(c.byId(id)!.status, ReservationStatus.driverEnRoute);
    expect(c.byId(id)!.revealsDriver, isTrue);
    c.dispose();
  });

  test('demo composition never resurrects a ride already past the '
      'No-driver-found deadline', () async {
    final scope = AppScope.composeForEnvironment(demo);
    addTearDown(scope.disposeForTest);
    final c = scope.reservations;
    final ride = await schedule(c);
    final id = ride.reservationId;

    // App was closed across pickup: the first tick happens at T+6.
    final late = pickupAt.add(const Duration(minutes: 6));
    await c.startLiveIfDue(now: late);
    final after = c.byId(id)!;
    expect(after.driver, isNull);
    expect(after.status.hasDriver, isFalse);
    expect(c.isNoDriverFound(after, now: late), isTrue);
    expect(c.noDriverFound(now: late).map((r) => r.reservationId), [id]);
  });

  group('demo composition, Home chrono with a fake clock', () {
    late AppScope scope;
    late ReservationController c;
    late DateTime now;
    late _LiveRouteCounter liveRoutes;

    Future<void> pumpHome(WidgetTester tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(375, 812),
          minTextAdapt: true,
          splitScreenMode: true,
          ensureScreenSize: true,
          builder: (_, __) => MaterialApp(
            navigatorObservers: [liveRoutes],
            home: Scaffold(
              body: Center(
                child: HomeReservationChrono(controller: c, now: () => now),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    Finder face() => find.descendant(
      of: find.byType(HomeReservationChrono),
      matching: find.byType(CustomPaint),
    );

    void expectRing(WidgetTester tester, Color color) {
      expect(
        tester.renderObject(face().first),
        paints..circle(color: color, style: PaintingStyle.stroke),
      );
    }

    void expectBadge(String key) {
      expect(find.byKey(ValueKey<String>(key)), findsOneWidget);
    }

    /// One 30 s chrono tick at the current fake time.
    Future<void> tick(WidgetTester tester) async {
      await tester.pump(const Duration(seconds: 30));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> pumpUntil(
      WidgetTester tester,
      bool Function() done, {
      int maxSeconds = 90,
    }) async {
      for (var i = 0; i < maxSeconds * 4 && !done(); i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
    }

    setUp(() {
      scope = AppScope.composeForEnvironment(demo);
      c = scope.reservations;
      liveRoutes = _LiveRouteCounter();
    });

    tearDown(() => scope.disposeForTest());

    testWidgets('full lifecycle: ring per step, live screen opens exactly once '
        'at en route, store ends completed, no reopen afterwards', (
      tester,
    ) async {
      final id = (await schedule(c)).reservationId;
      now = pickupAt.subtract(const Duration(minutes: 40));
      await pumpHome(tester);

      // 1. Scheduled, far out: no driver, countdown shown.
      expect(c.byId(id)!.status, ReservationStatus.scheduled);
      expect(c.byId(id)!.driver, isNull);
      expect(find.text('40m'), findsOneWidget);
      // Phase 111: no driver yet -> neutral ring + clock badge (was: green
      // ring, which wrongly read as "confirmed").
      expectRing(tester, _neutralRing);
      expectBadge('reservation-chrono-badge-booked');
      expect(liveRoutes.pushes, 0);

      // 2. T-30: mock dispatch assigns a driver (identity known), check badge.
      now = pickupAt.subtract(const Duration(minutes: 30));
      await tick(tester);
      final assigned = c.byId(id)!;
      expect(assigned.status, ReservationStatus.driverAssigned);
      expect(assigned.driver?.firstName, isIn(['Elin', 'Johan', 'Amina']));
      expect(find.text('30m'), findsOneWidget);
      // Phase 111: driver assigned -> neutral ring + check badge (was: green
      // ring).
      expectRing(tester, _neutralRing);
      expectBadge('reservation-chrono-badge-confirmed');
      expect(find.byType(WaitingForDriver), findsNothing);
      expect(liveRoutes.pushes, 0);

      // 3. T-3: still assigned, live screen not opened yet.
      now = pickupAt.subtract(const Duration(minutes: 3));
      await tick(tester);
      expect(c.byId(id)!.status, ReservationStatus.driverAssigned);
      expect(liveRoutes.pushes, 0);

      // 4. T-2: en route -> the live screen opens, once.
      now = pickupAt.subtract(const Duration(minutes: 2));
      await tick(tester);
      expect(c.byId(id)!.status, ReservationStatus.driverEnRoute);
      expect(find.byType(WaitingForDriver), findsOneWidget);
      expect(liveRoutes.pushes, 1);
      expect(find.textContaining(assigned.driver!.firstName), findsWidgets);

      // 5. Accelerated mock trip: arrived -> in progress -> completed.
      await pumpUntil(
        tester,
        () => c.byId(id)!.status == ReservationStatus.driverArrived,
      );
      expect(c.byId(id)!.status, ReservationStatus.driverArrived);
      expect(liveRoutes.pushes, 1);

      await pumpUntil(
        tester,
        () => c.byId(id)!.status == ReservationStatus.inProgress,
      );
      expect(c.byId(id)!.status, ReservationStatus.inProgress);
      expect(find.text('Ride in progress'), findsOneWidget);
      expect(liveRoutes.pushes, 1);

      await pumpUntil(
        tester,
        () => find.byType(RideCompleted).evaluate().isNotEmpty,
      );
      expect(c.byId(id)!.status, ReservationStatus.completed);
      expect(c.upcoming(), isEmpty);
      expect(find.byType(RideCompleted), findsOneWidget);
      expect(find.byType(WaitingForDriver), findsNothing);

      // 6. Done -> Home. Further ticks never reopen the finished ride.
      final done = find.byKey(const ValueKey<String>('ride-completed-done'));
      await tester.ensureVisible(done);
      await tester.tap(done);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(RideCompleted), findsNothing);
      for (var i = 0; i < 4; i++) {
        now = now.add(const Duration(seconds: 30));
        await tick(tester);
      }
      expect(find.byType(WaitingForDriver), findsNothing);
      expect(liveRoutes.pushes, 1);
      expect(c.byId(id)!.status, ReservationStatus.completed);
      expect(face(), findsNothing, reason: 'no upcoming ride -> no chrono');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('No driver found deadline still works when the app first '
        'ticks after T+5 (red ring, prompt, no driver)', (tester) async {
      final id = (await schedule(c)).reservationId;
      now = pickupAt.add(const Duration(minutes: 6));
      await pumpHome(tester);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(c.byId(id)!.driver, isNull);
      expect(
        find.byKey(const Key('reservation-chrono-no-driver')),
        findsOneWidget,
      );
      expectRing(tester, HomeReservationChrono.noDriver);
      expect(find.text('No driver found'), findsOneWidget);
      expect(liveRoutes.pushes, 0);

      await tester.tap(find.byKey(const Key('reservation-no-driver-cancel')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(c.byId(id)!.status, ReservationStatus.cancelled);
      expect(
        c.byId(id)!.cancellationReason,
        ReservationController.noDriverFoundReason,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('rider cancel mid-trip still works and the mock trip never '
        'overwrites it', (tester) async {
      final id = (await schedule(c)).reservationId;
      now = pickupAt.subtract(const Duration(minutes: 30));
      await pumpHome(tester);
      expect(c.byId(id)!.status, ReservationStatus.driverAssigned);

      now = pickupAt.subtract(const Duration(minutes: 2));
      await tick(tester);
      expect(c.byId(id)!.status, ReservationStatus.driverEnRoute);
      expect(liveRoutes.pushes, 1);

      // The rider's own cancel path on the live screen, as today.
      Future<void> frames([int n = 8]) async {
        for (var i = 0; i < n; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      await tester.tap(find.byIcon(Icons.close_rounded).first);
      await frames();
      await tester.tap(find.text('Cancel request'));
      await frames();
      await tester.tap(find.text('Plans changed'));
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel ride'));
      await frames(12);
      expect(c.byId(id)!.status, ReservationStatus.cancelled);
      expect(c.byId(id)!.cancellationReason, isNotNull);
      expect(find.byType(WaitingForDriver), findsNothing);
      expect(c.upcoming(), isEmpty);

      // Well past every mock trip step: the cancel stands.
      for (var i = 0; i < 4; i++) {
        now = now.add(const Duration(seconds: 30));
        await tick(tester);
      }
      expect(c.byId(id)!.status, ReservationStatus.cancelled);
      expect(liveRoutes.pushes, 1);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('a tap on a stale frame never opens the live screen for a '
        'ride that has just completed (reopen guard)', (tester) async {
      final id = (await schedule(c)).reservationId;
      now = pickupAt.subtract(const Duration(minutes: 40));
      // Park Home under a second route, then put the ride on the road by
      // hand, so the chrono does not auto-open it before the race below.
      await pumpHome(tester);
      final nav = tester.state<NavigatorState>(find.byType(Navigator));
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('elsewhere')),
        ),
      );
      await tester.pumpAndSettle();
      await c.applyDriverAssignment(
        id,
        driver: const ReservationDriver(
          firstName: 'Amina',
          rating: 4.9,
          vehicle: 'Tesla Model Y',
          plate: 'MVR 316',
        ),
      );
      await c.update(
        id,
        const ReservationPatch(status: ReservationStatus.driverEnRoute),
      );
      expect(c.byId(id)!.revealsDriver, isTrue);
      nav.pop();
      await tester.pumpAndSettle();
      // Home is current again; the chrono's last built frame still holds the
      // en-route snapshot. The ride completes before the next frame…
      final before = liveRoutes.pushes;
      await c.update(
        id,
        const ReservationPatch(status: ReservationStatus.completed),
      );
      // …and the rider taps the (stale) chrono in that same frame.
      await tester.tap(find.byType(HomeReservationChrono), warnIfMissed: false);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(c.byId(id)!.status, ReservationStatus.completed);
      expect(liveRoutes.pushes, before, reason: 'finished ride reopened');
      expect(find.byType(WaitingForDriver), findsNothing);
      expect(find.byType(RideCompleted), findsNothing);

      // Let any pending mock-trip step fire (it must not resurrect the ride).
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(seconds: 30));
      }
      expect(c.byId(id)!.status, ReservationStatus.completed);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });
}

class _LiveRouteCounter extends NavigatorObserver {
  int pushes = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route.settings.name == AppRoutes.reservationLive) pushes += 1;
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute?.settings.name == AppRoutes.reservationLive) pushes += 1;
  }
}
