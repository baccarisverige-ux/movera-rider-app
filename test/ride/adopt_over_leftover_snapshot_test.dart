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
import 'package:movera_rider/features/finding_driver/presentation/finding_drivers.dart';
import 'package:movera_rider/features/history/data/on_demand_ride_history_store.dart';
import 'package:movera_rider/features/ride_booking/application/ride_restore_coordinator.dart';
import 'package:movera_rider/features/ride_booking/application/rider_trip_watch.dart';
import 'package:movera_rider/features/ride_booking/data/active_trip_repositories.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/active_trip_repository.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Supervisor S5 / owner 2026-11-07: a snapshot left on this device (an
/// ended, stale or finished ride of another trip) blocked adopting the
/// booked trip the server reports: the rider stayed on Home, or saw the old
/// receipt. Only a live ride stored here (a search or a trip) wins. The fake
/// server follows movera-server src/trips/service.ts activeTrip().
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

  RideSnapshot left(RideStatus s, {DateTime? at, String id = 'ride_old'}) =>
      RideSnapshot(
        status: s,
        savedAt: at ?? DateTime.now(),
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

  final cases = <String, RideSnapshot Function()>{
    'terminal cancelledByRider': () => left(RideStatus.cancelledByRider),
    'stale findingDriver (1 h)': () => left(
      RideStatus.findingDriver,
      at: DateTime.now().subtract(const Duration(hours: 1)),
    ),
    'stale driverArriving (7 h)': () => left(
      RideStatus.driverArriving,
      at: DateTime.now().subtract(const Duration(hours: 7)),
    ),
    'ratingPending other ride, suppressRestore false': () =>
        left(RideStatus.ratingPending),
    'paymentProcessing other ride, suppressRestore false': () =>
        left(RideStatus.paymentProcessing),
    'rideOptionsReady (home surface, non-terminal)': () =>
        left(RideStatus.rideOptionsReady),
  };

  group('a leftover snapshot does not block adopting the booked trip', () {
    for (final entry in cases.entries) {
      test(
        '${entry.key} + booked driver_to_pickup -> first tick Waiting',
        () async {
          await RideSnapshotStore.save(entry.value());
          final replaced = <Widget>[];
          final c = coordinator(
            server('scheduled', 'driver_to_pickup'),
            replaced,
          );
          await watchFor(c).check();
          expect(
            replaced.isEmpty ? null : replaced.last.runtimeType,
            WaitingForDriver,
            reason: 'roots: ${replaced.map((w) => w.runtimeType).toList()}',
          );
          expect((await RideSnapshotStore.read())?.rideId, 'trp_1');
        },
      );
    }

    test('ratingPending of the ride just closed (suppressRestore true) + '
        'booked driver_to_pickup -> first tick Waiting', () async {
      AppScope.instance.ride
        ..restoreFromBackend(RideStatus.ratingPending, id: 'ride_old')
        ..localTransition(RideStatus.closed);
      await RideSnapshotStore.save(left(RideStatus.ratingPending));
      final replaced = <Widget>[];
      final c = coordinator(server('scheduled', 'driver_to_pickup'), replaced);
      await watchFor(c).check();
      expect(
        replaced.isEmpty ? null : replaced.last.runtimeType,
        WaitingForDriver,
      );
    });

    test('the replaced receipt of the other ride is kept in History', () async {
      await RideSnapshotStore.save(left(RideStatus.ratingPending));
      final c = coordinator(
        server('scheduled', 'driver_to_pickup'),
        <Widget>[],
      );
      await watchFor(c).check();
      final history = await OnDemandRideHistoryStore.read();
      expect(
        history.map((r) => r.reservationId),
        contains('ondemand-ride_old'),
      );
    });

    test('supervisor #536: stale server answer for the ride whose receipt is '
        'stored (just closed here) does not reopen its trip', () async {
      AppScope.instance.ride
        ..restoreFromBackend(RideStatus.ratingPending, id: 'trp_1')
        ..localTransition(RideStatus.closed);
      await RideSnapshotStore.save(left(RideStatus.ratingPending, id: 'trp_1'));
      final replaced = <Widget>[];
      final c = coordinator(server('live', 'in_trip'), replaced);
      await watchFor(c).check();
      expect(
        replaced.whereType<WaitingForDriver>(),
        isEmpty,
        reason: 'roots: ${replaced.map((w) => w.runtimeType).toList()}',
      );
    });

    test('same ride receipt stored, suppressRestore false: a stale server '
        'answer still does not reopen its trip', () async {
      await RideSnapshotStore.save(left(RideStatus.ratingPending, id: 'trp_1'));
      final replaced = <Widget>[];
      final c = coordinator(server('live', 'in_trip'), replaced);
      await watchFor(c).check();
      expect(
        replaced.whereType<WaitingForDriver>(),
        isEmpty,
        reason: 'roots: ${replaced.map((w) => w.runtimeType).toList()}',
      );
    });

    test(
      "this device's own fresh search still wins over the server trip",
      () async {
        await RideSnapshotStore.save(left(RideStatus.bookingRequested));
        final replaced = <Widget>[];
        final c = coordinator(
          server('scheduled', 'driver_to_pickup'),
          replaced,
        );
        await watchFor(c).check();
        expect(replaced.last, isA<FindingDrivers>());
        expect((await RideSnapshotStore.read())?.rideId, 'ride_old');
      },
    );
  });
}
