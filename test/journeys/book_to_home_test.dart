import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/navigator_key.dart';
import 'package:movera_rider/app/router/routes.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/active_ride/presentation/driver_arrived_sheet.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/presentation/finding_drivers.dart';
import 'package:movera_rider/features/home/presentation/home.dart';
import 'package:movera_rider/features/pickup/presentation/set_pickup_page.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_complete/application/ride_complete_controller.dart';
import 'package:movera_rider/features/ride_complete/data/last_completed_ride.dart';
import 'package:movera_rider/features/ride_complete/data/ride_feedback_repository.dart';
import 'package:movera_rider/features/ride_complete/presentation/ride_completed.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Phase 69 journey coverage must exercise the production completion surface
/// through real taps and the named Rider route contract. It intentionally does
/// not recreate RideCompleted logic in a test stand-in.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    AppScope.instance.ride
      ..rideId = 'journey-book-1'
      ..status = RideStatus.ratingPending;
    // The continuous journey test below completes a real trip with a real
    // assigned driver, which populates this process-global snapshot. Clear
    // it so later tests in this file see the same driver-less state they
    // would if run in isolation, instead of inheriting a leaked driver name.
    LastCompletedRide.clear();
  });

  testWidgets(
    'Phase 85 continuous Home -> destination -> quote -> Book -> Finding -> assigned -> Waiting -> trip -> Complete -> rating/tip -> Home',
    (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // flutter_test defaults defaultTargetPlatform to android, which makes
      // SecureTokenStore route the geocode/booking calls this journey makes
      // through the live flutter_secure_storage platform channel. With no
      // native host to answer it, that channel call never completes, hanging
      // every authenticated request made from inside the pumped widget tree.
      // Force a desktop platform so SecureTokenStore falls back to its
      // in-memory store, matching how the app actually behaves on web/Linux.
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      FindingDriverController.active = null;
      AppScope.instance.ride
        ..rideId = null
        ..status = RideStatus.idle
        ..suppressRestore = false
        ..authoritativeVersion = null
        ..authoritativeUpdatedAt = null;

      final realtime = AppScope.instance.rideRealtime;
      expect(realtime, isA<MockRideRealtime>());

      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          minTextAdapt: true,
          splitScreenMode: true,
          builder: (_, __) =>
              MaterialApp(navigatorKey: moveraNavigatorKey, home: const Home()),
        ),
      );
      // Real frames, so Home can settle (the promotion ticket may seat the
      // sheet a few frames after launch).
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.byType(Home), findsOneWidget);
      expect(find.text('Where to?'), findsOneWidget);

      await tester.tap(find.text('Where to?'));
      for (
        var i = 0;
        i < 40 && find.byType(TextField).evaluate().length < 2;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      final routeFields = find.byType(TextField);
      expect(routeFields, findsAtLeastNWidgets(2));

      // The sheet fields exist before the smooth-sheet route has fully reached
      // its resting position. Wait past the production 380 ms open motion so
      // the test taps the same settled geometry a Rider sees.
      await tester.pump(const Duration(milliseconds: 450));

      await tester.enterText(routeFields.at(0), 'Stockholm Central');
      await tester.pump();
      await tester.enterText(routeFields.at(1), 'Arlanda Airport');
      await tester.pump();

      // No Next button: tapping a real suggested address moves on.
      final suggestion = find.text('Airport Terminal 5', findRichText: true);
      var arlanda = find.textContaining('Arlanda Airport', findRichText: true);
      for (var i = 0; i < 30 && arlanda.evaluate().length < 2; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        arlanda = find.textContaining('Arlanda Airport', findRichText: true);
      }
      expect(find.text('Next'), findsNothing);
      expect(suggestion, findsNothing);
      final pick = find.textContaining(
        'Stockholm Arlanda Airport',
        findRichText: true,
      );
      expect(pick, findsWidgets);
      await tester.tap(pick.first);
      // The route sheet closes, both addresses are normalized in parallel, and
      // the production category selector is pushed.
      for (
        var i = 0;
        i < 30 && find.byType(SelectRide).evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(SelectRide), findsOneWidget);

      // Quotes are backend-authored even in demo/test composition. Wait for
      // the category CTA to become actionable instead of bypassing selection.
      Finder selectMovera = find.text('Select Movera');
      for (var i = 0; i < 40 && selectMovera.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        selectMovera = find.text('Select Movera');
      }
      expect(selectMovera, findsOneWidget);
      await tester.ensureVisible(selectMovera);
      await tester.tap(selectMovera);

      // Set pickup opens after Book, with the pickup preselected.
      for (
        var i = 0;
        i < 40 && find.byType(SetPickupPage).evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(SetPickupPage), findsOneWidget);
      final confirmSearch = find.text('Confirm and search');
      expect(confirmSearch, findsOneWidget);
      // P5-R6: Set pickup finishes opening before the rider confirms (a tap
      // while it slides in is the second tap of a double tap and is ignored).
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(confirmSearch);

      for (
        var i = 0;
        i < 40 && find.byType(FindingDrivers).evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(FindingDrivers), findsOneWidget);
      expect(AppScope.instance.ride.status, RideStatus.findingDriver);
      final rideId = AppScope.instance.ride.rideId;
      expect(rideId, isNotNull);
      expect(rideId!.trim(), isNotEmpty);

      final mock = realtime as MockRideRealtime;
      mock.assignNow();
      for (
        var i = 0;
        i < 50 && find.byType(WaitingForDriver).evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(WaitingForDriver), findsOneWidget);
      expect(AppScope.instance.ride.rideId, rideId);
      expect(AppScope.instance.ride.status.isMatched, isTrue);

      mock.markArrivedForTest();
      await tester.pump(const Duration(milliseconds: 200));

      // The driver-arrived sheet is a real pushed route: while it is open,
      // WaitingForDriver.isCurrent is false and it deliberately withholds the
      // trip-completed transition until the rider acknowledges arrival — the
      // same "popup waits for a child route to return" contract certified
      // elsewhere for this screen. Acknowledge it here or the trip timers
      // below fire into a route that never drains them.
      for (
        var i = 0;
        i < 20 && find.byType(DriverArrivedSheet).evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(DriverArrivedSheet), findsOneWidget);
      // Let the sheet's entrance animation settle onto its resting geometry
      // before hit-testing its CTA — the same wait every other sheet tap in
      // this journey already needs.
      await tester.pump(const Duration(milliseconds: 350));
      final onTheWay = find.text("I'm on the way");
      await tester.ensureVisible(onTheWay);
      await tester.tap(onTheWay);
      for (
        var i = 0;
        i < 20 && find.byType(DriverArrivedSheet).evaluate().isNotEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(DriverArrivedSheet), findsNothing);

      await tester.pump(const Duration(seconds: 9));
      for (var i = 0; i < 7; i++) {
        await tester.pump(const Duration(seconds: 3));
      }
      await tester.pump(const Duration(seconds: 2));

      for (
        var i = 0;
        i < 30 && find.byType(RideCompleted).evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(RideCompleted), findsOneWidget);
      expect(AppScope.instance.ride.rideId, rideId);

      // Let the backend-authored post-trip payment/rating statuses settle.
      for (
        var i = 0;
        i < 30 && find.text('How was your trip').evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('How was your trip'), findsOneWidget);
      // This journey completes with a real assigned driver, so the tip
      // header reads "Tip <name>" rather than the driver-less "Tip your
      // driver" fallback the standalone completion test below exercises.
      expect(
        find.textContaining('Tip ', findRichText: true),
        findsWidgets,
        reason: 'tip surface should greet the rider with a tip prompt',
      );

      final star = find.byIcon(Icons.star_rounded).first;
      await tester.ensureVisible(star);
      await tester.tap(star);
      await tester.pump();

      final tip = find.text('20 kr').first;
      await tester.ensureVisible(tip);
      await tester.tap(tip);
      await tester.pump();
      expect(find.text('20 kr selected.'), findsOneWidget);

      final done = find.byKey(const ValueKey<String>('ride-completed-done'));
      await tester.ensureVisible(done);
      await tester.tap(done);

      for (var i = 0; i < 50 && find.byType(Home).evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.byType(Home), findsOneWidget);
      expect(moveraNavigatorKey.currentState!.canPop(), isFalse);
      expect(AppScope.instance.ride.status, RideStatus.closed);
      expect(AppScope.instance.ride.rideId, rideId);
      expect(await RideSnapshotStore.read(), isNull);
      // The next booking starts from "Where to?", not the last destination.
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Where to?'), findsOneWidget);
      expect(find.textContaining('Arlanda'), findsNothing);

      // No delayed assignment or stage timer may leak out of this one journey.
      mock.unsubscribe();
      await tester.pump();

      // The framework's end-of-test invariant check runs synchronously right
      // after this callback returns, before any addTearDown callback fires,
      // so the override must be cleared here rather than relying on the
      // addTearDown registered above.
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('completed ride -> rating/tip surface -> Done -> Home', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(1200, 1600),
        builder: (_, __) => MaterialApp(
          navigatorKey: moveraNavigatorKey,
          home: const Scaffold(body: Text('journey-home')),
        ),
      ),
    );

    final realtime = MockRideRealtime();
    final backend = InProcessMockClient();
    backend.rides['journey-book-1'] = {
      'id': 'journey-book-1',
      'status': 'ratingPending',
    };
    moveraNavigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: AppRoutes.rideCompleted),
        builder: (_) => RideCompleted(
          status: RideStatus.ratingPending,
          rideId: 'journey-book-1',
          realtime: realtime,
          controller: RideCompleteController(
            feedback: RideFeedbackRepository(api: ApiClient(client: backend)),
          ),
          showConnectionBanner: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      ModalRoute.of(tester.element(find.byType(RideCompleted)))?.settings.name,
      AppRoutes.rideCompleted,
    );
    expect(AppScope.instance.ride.rideId, 'journey-book-1');
    expect(AppScope.instance.ride.status, RideStatus.ratingPending);
    expect(find.text('How was your trip'), findsOneWidget);
    expect(find.text('Tip your driver'), findsOneWidget);

    final star = find.byIcon(Icons.star_rounded).first;
    await tester.ensureVisible(star);
    await tester.tap(star);
    await tester.pump();

    final tip = find.text('20 kr').first;
    await tester.ensureVisible(tip);
    await tester.tap(tip);
    await tester.pump();
    expect(find.text('20 kr selected.'), findsOneWidget);
    expect(backend.rides['journey-book-1']!['feedback'], isNull);

    final done = find.byKey(const ValueKey<String>('ride-completed-done'));
    await tester.ensureVisible(done);
    backend.failNext = true;
    await tester.tap(done);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('completion-submit-error')),
      findsOneWidget,
    );
    expect(backend.rides['journey-book-1']!['feedback'], isNull);
    expect(AppScope.instance.ride.status, RideStatus.ratingPending);

    await tester.tap(done);
    await tester.pumpAndSettle();
    final feedback =
        backend.rides['journey-book-1']!['feedback'] as Map<String, dynamic>;
    expect(feedback['rating'], isA<num>());
    expect(feedback['tipMinor'], 2000);
    expect(feedback['currency'], 'SEK');

    expect(find.text('journey-home'), findsOneWidget);
    expect(moveraNavigatorKey.currentState!.canPop(), isFalse);
    expect(AppScope.instance.ride.status, RideStatus.closed);

    // This journey owns the injected transport. Dispose it inside the fake
    // async test body so its assignment timer is cancelled before Flutter's
    // end-of-test timer invariant runs; addTearDown is too late for that check.
    realtime.dispose();
    await tester.pump();
  });

  testWidgets(
    'accepted feedback -> close failure -> changed feedback submits new intent',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(1200, 1600),
          builder: (_, __) => MaterialApp(
            navigatorKey: moveraNavigatorKey,
            home: const Scaffold(body: Text('journey-home')),
          ),
        ),
      );

      final realtime = MockRideRealtime();
      final backend = InProcessMockClient();
      backend.rides['journey-book-1'] = {
        'id': 'journey-book-1',
        'status': 'ratingPending',
      };
      var closeAttempts = 0;
      moveraNavigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: AppRoutes.rideCompleted),
          builder: (_) => RideCompleted(
            status: RideStatus.ratingPending,
            rideId: 'journey-book-1',
            realtime: realtime,
            controller: RideCompleteController(
              feedback: RideFeedbackRepository(api: ApiClient(client: backend)),
            ),
            showConnectionBanner: false,
            onClose: (_) async {
              closeAttempts += 1;
              if (closeAttempts == 1) {
                throw StateError('History close failed');
              }
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      final firstStar = find.byIcon(Icons.star_rounded).first;
      await tester.ensureVisible(firstStar);
      await tester.tap(firstStar);
      await tester.pump();

      final firstTip = find.text('20 kr').first;
      await tester.ensureVisible(firstTip);
      await tester.tap(firstTip);
      await tester.pump();

      final done = find.byKey(const ValueKey<String>('ride-completed-done'));
      await tester.ensureVisible(done);
      await tester.tap(done);
      await tester.pumpAndSettle();

      expect(closeAttempts, 1);
      expect(
        find.byKey(const ValueKey('completion-submit-error')),
        findsOneWidget,
      );
      final firstFeedback =
          backend.rides['journey-book-1']!['feedback'] as Map<String, dynamic>;
      expect(firstFeedback['tipMinor'], 2000);
      expect(backend.idempotency.length, 1);

      final changedStar = find.byIcon(Icons.star_rounded).at(2);
      await tester.ensureVisible(changedStar);
      await tester.tap(changedStar);
      await tester.pump();

      final changedTip = find.text('30 kr').first;
      await tester.ensureVisible(changedTip);
      await tester.tap(changedTip);
      await tester.pump();

      await tester.ensureVisible(done);
      await tester.tap(done);
      await tester.pumpAndSettle();

      expect(closeAttempts, 2);
      final changedFeedback =
          backend.rides['journey-book-1']!['feedback'] as Map<String, dynamic>;
      expect(changedFeedback['rating'], 3);
      expect(changedFeedback['tipMinor'], 3000);
      expect(changedFeedback['currency'], 'SEK');
      expect(backend.idempotency.length, 2);

      realtime.dispose();
      await tester.pump();
    },
  );
}
