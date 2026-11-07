import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/router/ride_stage_observer.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/home/presentation/home.dart';
import 'package:movera_rider/features/ride_booking/application/ride_restore_coordinator.dart';
import 'package:movera_rider/features/ride_booking/application/rider_trip_watch.dart';
import 'package:movera_rider/features/ride_booking/data/active_trip_repositories.dart';
import 'package:movera_rider/features/ride_booking/domain/active_trip_repository.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Supervisor S5, 2026-11-07: a second path to the booked ride stuck on
/// Home. A cold restart restored a ride at the root ([showing] finding /
/// waiting / complete); its snapshot ended, resume swapped Home in but left
/// [showing] as it was, so RiderTripWatch believed a ride was on screen and
/// never adopted the booked trip. The fake server follows movera-server
/// src/trips/service.ts activeTrip(): a scheduled trip only once it reached
/// driver_to_pickup; 204 otherwise.
/// driver_to_pickup; 204 otherwise (completed is terminal).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const staging = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://api.example.test',
  );
  const terminal = {
    'completed',
    'cancelled_by_rider',
    'cancelled_by_driver',
    'cancelled_by_admin',
    'cancelled_by_system',
    'no_show',
    'expired',
    'failed',
  };

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

  Map<String, Object?> proj(String kind, String status) => {
    'tripId': 'trp_1',
    'rideId': 'trp_1',
    'kind': kind,
    'status': status,
    'version': 7,
    'sequence': 7,
    'categoryId': 'economy',
    if (kind == 'scheduled') 'scheduledAt': '2026-11-07T17:05:00Z',
    'createdAt': '2026-11-07T15:00:00Z',
    'updatedAt': '2026-11-07T17:00:00Z',
    'pickup': {'address': 'Sergels torg', 'lat': 59.3326, 'lng': 18.0649},
    'dropoff': {'address': 'Medborgarplatsen', 'lat': 59.3143, 'lng': 18.0735},
    'stops': <Object>[],
    'fare': {'amountMinor': 24200, 'currency': 'SEK'},
    'paymentMethod': 'cash',
    if (status == 'completed') 'paymentStatus': 'captured',
    if (status == 'completed') 'ratingStatus': 'pending',
    if (!(kind == 'scheduled' && status == 'accepted') &&
        status != 'searching' &&
        status != 'offered')
      'driver': {'driverId': 'drv_1', 'firstName': 'Ali'},
  };

  /// [drove]: the scheduled trip reached driver_to_pickup at least once.
  ActiveTripRepository server(String kind, String status, {bool drove = true}) {
    final api = ApiClient(
      client: MockClient((request) async {
        final shown = !terminal.contains(status) && (kind == 'live' || drove);
        return shown
            ? http.Response(
                jsonEncode(proj(kind, status)),
                200,
                headers: {'content-type': 'application/json'},
              )
            : http.Response('', 204);
      }),
      env: staging,
    );
    return ApiActiveTripRepository(api: api);
  }

  RideRestoreCoordinator coordinator(
    ActiveTripRepository repo,
    List<Widget> replaced, {
    bool atRoot = true,
  }) =>
      RideRestoreCoordinator(
          resync: (_) async {},
          authRequired: () => false,
          serverActiveTrip: repo.fetchActive,
          pendingCancel: (_) async => null,
        )
        ..debugAtRoot = (() => atRoot)
        ..onReplaceRoot = replaced.add;

  RiderTripWatch watchFor(RideRestoreCoordinator c) => RiderTripWatch(
    // Same as RiderTripWatch._defaultShowsHome, on this coordinator.
    showsHome: () =>
        c.showing == RestoredSurface.home &&
        !RideStageRouteObserver.rideOnScreen,
    adopt: () async => c.resumeIfNeeded(),
    bookedOnTheWay: () async => false,
  );

  group('RUNNING vs COLD: showing stuck after root Home swap', () {
    for (final surface in [
      RestoredSurface.finding,
      RestoredSurface.waiting,
      RestoredSurface.complete,
    ]) {
      test('root was restored ${surface.name}, its snapshot ended/cleared, '
          'resume swaps Home in; later booked driver_to_pickup -> Waiting '
          'within one poll', () async {
        final replaced = <Widget>[];
        final c = coordinator(
          server('scheduled', 'accepted', drove: false),
          replaced,
        );
        c.showing = surface; // cold restart had restored this ride at root
        await c.resumeIfNeeded(); // snapshot gone: root becomes Home
        final homeShown = replaced.isNotEmpty && replaced.last is Home;
        expect(homeShown, isTrue);
        // Driver now starts: server returns the booked trip.
        final c2 =
            RideRestoreCoordinator(
                resync: (_) async {},
                authRequired: () => false,
                serverActiveTrip: server(
                  'scheduled',
                  'driver_to_pickup',
                ).fetchActive,
                pendingCancel: (_) async => null,
              )
              ..debugAtRoot = (() => true)
              ..onReplaceRoot = replaced.add
              ..showing = c.showing; // same in-memory state as the running app
        await watchFor(c2).check();
        expect(replaced.last, isA<WaitingForDriver>());
      });
    }
    test('control: cold start (fresh memory) opens the same trip', () async {
      final c = coordinator(
        server('scheduled', 'driver_to_pickup'),
        <Widget>[],
      );
      expect(await c.root(), isA<WaitingForDriver>());
    });
  });
}
