import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/navigator_key.dart';
import 'package:movera_rider/app/router/ride_stage_observer.dart';
import 'package:movera_rider/app/router/routes.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/ride_booking/application/ride_restore_coordinator.dart';
import 'package:movera_rider/features/ride_booking/application/rider_trip_watch.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Owner 2026-11-07 "4. Passager : retours en arrière" (Rules
/// plan/AUDIT-TRIP-LIFECYCLE-2026-11-07.md).
///
/// 4a: Finding / Waiting / the trip / the receipt are pushed over Home, so
/// `RideRestoreCoordinator.showing` stayed `home` and every 8 s watch tick
/// (and every resume) ran the Home-only "open the server's active trip",
/// which popped the ride on screen to the first route and rebuilt it.
///
/// 4b: after Done on the receipt, a server "active trip" that is already
/// finished (completed / payment / rating pending) was saved and the receipt
/// opened again.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    RideSnapshotStore.epoch = 0;
    RideRestoreCoordinator.instance.showing = RestoredSurface.home;
    AppScope.instance.ride
      ..rideId = null
      ..suppressRestore = false
      ..authoritativeVersion = null
      ..authoritativeUpdatedAt = null
      ..restoreFromBackend(RideStatus.idle);
  });

  RideSnapshot trip(RideStatus status, {String id = 'ride_live'}) =>
      RideSnapshot(
        status: status,
        savedAt: DateTime.now(),
        pickupAddress: 'A',
        destinationAddress: 'B',
        pickupLat: 59.3,
        pickupLng: 18.0,
        destinationLat: 59.6,
        destinationLng: 17.9,
        rideType: 'Movera',
        price: 259,
        paymentMethod: 'Cash',
        rideId: id,
      );

  Future<void> app(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      navigatorKey: moveraNavigatorKey,
      navigatorObservers: [RideStageRouteObserver()],
      home: const Scaffold(body: Text('home')),
    ),
  );

  Future<void> push(WidgetTester tester, String name) async {
    moveraNavigatorKey.currentState!.push<void>(
      MaterialPageRoute(
        settings: RouteSettings(name: name),
        builder: (_) => Scaffold(body: Text(name)),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('4a: a ride on screen never triggers the Home adopt', () {
    for (final name in [
      AppRoutes.findingDriver,
      AppRoutes.waitingForDriver,
      AppRoutes.rideCompleted,
    ]) {
      testWidgets('watch tick with $name on screen does not adopt', (
        tester,
      ) async {
        await app(tester);
        await push(tester, name);
        var adopts = 0;
        var banner = 0;
        final watch = RiderTripWatch(
          adopt: () async => adopts++,
          bookedOnTheWay: () async {
            banner++;
            return false;
          },
        );
        await tester.runAsync(watch.check);
        expect(adopts, 0);
        expect(banner, 1);
      });
    }

    testWidgets('watch tick on Home still adopts', (tester) async {
      await app(tester);
      var adopts = 0;
      final watch = RiderTripWatch(
        adopt: () async => adopts++,
        bookedOnTheWay: () async => false,
      );
      await tester.runAsync(watch.check);
      expect(adopts, 1);
    });

    testWidgets('resume with Waiting pushed: no pop to first, no rebuild', (
      tester,
    ) async {
      await app(tester);
      await push(tester, AppRoutes.waitingForDriver);
      final replaced = <Widget>[];
      final restore = RideRestoreCoordinator(
        resync: (_) async {},
        authRequired: () => false,
        serverActiveTrip: () async => trip(RideStatus.driverArriving),
        pendingCancel: (_) async => null,
      )..onReplaceRoot = replaced.add;
      final page = await tester.runAsync(restore.resumeIfNeeded);
      await tester.pumpAndSettle();
      expect(page, isNull);
      expect(replaced, isEmpty);
      expect(find.text(AppRoutes.waitingForDriver), findsOneWidget);
      expect(moveraNavigatorKey.currentState!.canPop(), isTrue);
    });

    testWidgets('resume on Home still opens the live server trip', (
      tester,
    ) async {
      await app(tester);
      final replaced = <Widget>[];
      final restore = RideRestoreCoordinator(
        resync: (_) async {},
        authRequired: () => false,
        serverActiveTrip: () async => trip(RideStatus.driverArriving),
        pendingCancel: (_) async => null,
      )..onReplaceRoot = replaced.add;
      final page = await tester.runAsync(restore.resumeIfNeeded);
      expect(page, isA<WaitingForDriver>());
      expect(replaced.single, isA<WaitingForDriver>());
    });
  });

  group('4b: after Done a finished server trip is not adopted', () {
    for (final status in [
      RideStatus.tripCompleted,
      RideStatus.paymentProcessing,
      RideStatus.paymentFinalized,
      RideStatus.ratingPending,
    ]) {
      test('${status.name}: nothing saved, nothing re-opens', () async {
        final replaced = <Widget>[];
        final restore =
            RideRestoreCoordinator(
                resync: (_) async {},
                authRequired: () => false,
                serverActiveTrip: () async => trip(status, id: 'ride_done'),
                pendingCancel: (_) async => null,
              )
              ..debugAtRoot = (() => true)
              ..onReplaceRoot = replaced.add;
        // Done: snapshot cleared, then resumeIfNeeded (RideNavigator
        // openActiveTripAfterHome), then the next 8 s watch tick.
        await RideSnapshotStore.clear();
        expect(await restore.adoptServerActiveTrip(), isNull);
        expect(await restore.resumeIfNeeded(), isNull);
        expect(await restore.resumeIfNeeded(), isNull);
        expect(replaced, isEmpty);
        expect(await RideSnapshotStore.read(), isNull);
        expect(restore.showing, RestoredSurface.home);
      });
    }

    test(
      'a push tap for the ride just closed here does not reopen it',
      () async {
        AppScope.instance.ride
          ..restoreFromBackend(RideStatus.ratingPending, id: 'ride_done')
          ..localTransition(RideStatus.closed);
        expect(AppScope.instance.ride.suppressRestore, isTrue);
        final restore = RideRestoreCoordinator(
          resync: (_) async {},
          authRequired: () => false,
          serverActiveTrip: () async =>
              trip(RideStatus.ratingPending, id: 'ride_done'),
          pendingCancel: (_) async => null,
        );
        expect(
          await restore.adoptServerActiveTrip(expectedRideId: 'ride_done'),
          isNull,
        );
        expect(await RideSnapshotStore.read(), isNull);
      },
    );

    test('a live server trip is still adopted', () async {
      final restore = RideRestoreCoordinator(
        resync: (_) async {},
        authRequired: () => false,
        serverActiveTrip: () async => trip(RideStatus.tripInProgress),
        pendingCancel: (_) async => null,
      );
      expect((await restore.adoptServerActiveTrip())?.rideId, 'ride_live');
    });
  });
}
