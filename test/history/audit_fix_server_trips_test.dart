import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/features/finding_driver/presentation/finding_drivers.dart';
import 'package:movera_rider/features/home/presentation/home.dart';
import 'package:movera_rider/features/history/application/on_demand_history_controller.dart';
import 'package:movera_rider/features/history/data/ride_history_repositories.dart';
import 'package:movera_rider/features/history/domain/ride_history_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';
import 'package:movera_rider/features/ride_booking/application/ride_restore_coordinator.dart';
import 'package:movera_rider/features/ride_booking/data/active_trip_repositories.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FixedHistory implements RideHistoryRepository {
  _FixedHistory(this.rides);
  final List<Reservation> rides;

  @override
  Future<List<Reservation>> loadOnDemand() async => rides;
}

/// ARCH-12: the server is asked for "my current ride" and ride history
/// (contract C-5), so an empty device can still restore a live ride.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const demo = AppEnv(
    flavor: AppFlavor.demo,
    apiBaseUrl: 'https://api.demo.movera.invalid',
  );

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    RideSnapshotStore.epoch = 0;
    AppScope.instance.ride
      ..rideId = null
      ..suppressRestore = false
      ..restoreFromBackend(RideStatus.idle);
  });

  Map<String, dynamic> ride(String id, String status, {int version = 3}) => {
    'id': id,
    'status': status,
    'version': version,
    'updatedAt': '2026-10-14T09:00:00.000Z',
    'categoryId': 'comfort',
    'paymentMethodId': 'cash',
    'price': 319,
    'pickupAddress': 'Stockholm Central',
    'pickupLat': 59.3293,
    'pickupLng': 18.0686,
    'destinationAddress': 'Arlanda Airport',
    'destinationLat': 59.6519,
    'destinationLng': 17.9186,
  };

  test('the active trip is read from the server projection', () async {
    final mock = InProcessMockClient();
    final repository = ApiActiveTripRepository(
      api: ApiClient(client: mock, env: demo),
    );
    expect(await repository.fetchActive(), isNull);

    mock.rides['ride_done'] = ride('ride_done', 'cancelledByRider');
    mock.rides['ride_live'] = ride('ride_live', 'driver_to_pickup');
    final live = await repository.fetchActive();
    expect(live?.rideId, 'ride_live');
    expect(live?.status, RideStatus.driverArriving);
    expect(live?.version, 3);
    expect(live?.serverUpdatedAt, DateTime.utc(2026, 10, 14, 9));
    expect(live?.price, 319);
    expect(live?.pickupAddress, 'Stockholm Central');
  });

  test(
    'cold start with empty storage restores the server active trip',
    () async {
      final server = ride('ride_srv', 'findingDriver');
      final restore = RideRestoreCoordinator(
        resync: (_) async {},
        authRequired: () => false,
        serverActiveTrip: () async {
          final mock = InProcessMockClient()..rides['ride_srv'] = server;
          return ApiActiveTripRepository(
            api: ApiClient(client: mock, env: demo),
          ).fetchActive();
        },
      );
      final page = await restore.root();
      expect(page, isA<FindingDrivers>());
      expect(restore.showing, RestoredSurface.finding);
      expect((await RideSnapshotStore.read())?.rideId, 'ride_srv');
      expect(AppScope.instance.ride.rideId, 'ride_srv');
    },
  );

  test('a local snapshot is never replaced by the server trip', () async {
    await RideSnapshotStore.save(
      RideSnapshot(
        status: RideStatus.findingDriver,
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
        rideId: 'ride_local',
      ),
    );
    var asked = 0;
    final restore = RideRestoreCoordinator(
      serverActiveTrip: () async {
        asked++;
        return null;
      },
    );
    expect(await restore.adoptServerActiveTrip(), isNull);
    expect(asked, 0);
    expect((await RideSnapshotStore.read())?.rideId, 'ride_local');
  });

  test('a push for another ride does not adopt the server trip', () async {
    final mock = InProcessMockClient()
      ..rides['ride_srv'] = ride('ride_srv', 'driverAssigned');
    final restore = RideRestoreCoordinator(
      serverActiveTrip: ApiActiveTripRepository(
        api: ApiClient(client: mock, env: demo),
      ).fetchActive,
    );
    expect(
      await restore.adoptServerActiveTrip(expectedRideId: 'ride_other'),
      isNull,
    );
    expect(await RideSnapshotStore.read(), isNull);
    final adopted = await restore.adoptServerActiveTrip(
      expectedRideId: 'ride_srv',
    );
    expect(adopted?.rideId, 'ride_srv');
  });

  test('History reads finished trips from the server', () async {
    final mock = InProcessMockClient()
      ..rides['ride_a'] = ride('ride_a', 'paymentFinalized')
      ..rides['ride_b'] = ride('ride_b', 'cancelled_by_driver')
      ..rides['ride_live'] = ride('ride_live', 'findingDriver');
    final history = await ApiRideHistoryRepository(
      api: ApiClient(client: mock, env: demo),
    ).loadOnDemand();
    expect(history.map((r) => r.reservationId).toSet(), {
      'ondemand-ride_a',
      'ondemand-ride_b',
    });
    final cancelled = history.firstWhere(
      (r) => r.reservationId == 'ondemand-ride_b',
    );
    expect(cancelled.status, ReservationStatus.cancelled);
    expect(cancelled.price, 319);
  });

  test('History goes through the composed repository', () async {
    final record = (await ApiRideHistoryRepository(
      api: ApiClient(
        client: InProcessMockClient()
          ..rides['ride_a'] = ride('ride_a', 'tripCompleted'),
        env: demo,
      ),
    ).loadOnDemand()).single;
    final controller = OnDemandHistoryController(
      repository: _FixedHistory([record]),
    );
    expect((await controller.load()).single.reservationId, 'ondemand-ride_a');
    expect(AppScope.instance.rideHistory, isA<LocalRideHistoryRepository>());
  });

  Future<RideSnapshot?> serverTrip(String id) => ApiActiveTripRepository(
    api: ApiClient(
      client: InProcessMockClient()..rides[id] = ride(id, 'findingDriver'),
      env: demo,
    ),
  ).fetchActive();

  test('rider-u174: a slow active-trip lookup does not hold the cold start; '
      'a trip that arrives late still opens', () async {
    final lookup = Completer<RideSnapshot?>();
    final replaced = <Widget>[];
    final restore =
        RideRestoreCoordinator(
            resync: (_) async {},
            authRequired: () => false,
            serverActiveTrip: () => lookup.future,
          )
          ..debugAtRoot = (() => true)
          ..onReplaceRoot = replaced.add;
    final page = await restore.root().timeout(const Duration(seconds: 10));
    expect(page, isA<Home>());
    expect(restore.showing, RestoredSurface.home);

    lookup.complete(await serverTrip('ride_late'));
    await pumpEventQueue();
    expect(replaced.single, isA<FindingDrivers>());
    expect(restore.showing, RestoredSurface.finding);
    expect((await RideSnapshotStore.read())?.rideId, 'ride_late');
  });

  test('rider-67: a leftover suppressRestore from an earlier ride does not '
      'delete the trip a push tap just adopted', () async {
    // Ride A was closed on this device earlier.
    AppScope.instance.ride
      ..restoreFromBackend(RideStatus.ratingPending, id: 'ride_a')
      ..localTransition(RideStatus.closed);
    expect(AppScope.instance.ride.suppressRestore, isTrue);
    final replaced = <Widget>[];
    final restore =
        RideRestoreCoordinator(
            resync: (_) async {},
            authRequired: () => false,
            serverActiveTrip: () => serverTrip('ride_b'),
          )
          ..debugAtRoot = (() => true)
          ..onReplaceRoot = replaced.add;
    expect(
      (await restore.adoptServerActiveTrip(expectedRideId: 'ride_b'))?.rideId,
      'ride_b',
    );
    expect(await restore.resumeIfNeeded(), isA<FindingDrivers>());
    expect((await RideSnapshotStore.read())?.rideId, 'ride_b');
  });
}
