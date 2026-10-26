import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/finding_driver/data/pending_cancel_store.dart';
import 'package:movera_rider/features/finding_driver/presentation/finding_drivers.dart';
import 'package:movera_rider/features/home/presentation/home.dart';
import 'package:movera_rider/features/ride_booking/application/ride_restore_coordinator.dart';
import 'package:movera_rider/features/ride_booking/data/active_trip_repositories.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Owner, live test 2026-10-26: "How rider can book another ride while he
/// have ongoing ride !!! Must always display the ongoing ride !!! So can't
/// book another". The rider was on Select ride while the server still held
/// a ride for them. At start the app waits 2 s for the server's answer
/// (Render's free plan can take far longer to wake); a ride that came later
/// opened only if the rider was still on Home, not once they had moved on to
/// Where to or Select ride. Coming back to the app never asked the server.
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
      ..authoritativeVersion = null
      ..authoritativeUpdatedAt = null
      ..restoreFromBackend(RideStatus.idle);
  });

  Future<RideSnapshot?> serverTrip(String id, String status) =>
      ApiActiveTripRepository(
        api: ApiClient(
          client: InProcessMockClient()
            ..rides[id] = {
              'id': id,
              'status': status,
              'version': 3,
              'updatedAt': '2026-10-26T12:00:00.000Z',
              'categoryId': 'economy',
              'paymentMethodId': 'cash',
              'price': 147,
              'pickupAddress': 'Södertälje C',
              'pickupLat': 59.1955,
              'pickupLng': 17.6253,
              'destinationAddress': 'Hamngatan 1',
              'destinationLat': 59.3326,
              'destinationLng': 18.0649,
            },
          env: demo,
        ),
      ).fetchActive();

  RideSnapshot stored(RideStatus status, {DateTime? savedAt}) => RideSnapshot(
    status: status,
    savedAt: savedAt ?? DateTime.now(),
    pickupAddress: 'A',
    destinationAddress: 'B',
    pickupLat: 59.3,
    pickupLng: 18.0,
    destinationLat: 59.6,
    destinationLng: 17.9,
    rideType: 'Movera',
    price: 259,
    paymentMethod: 'Cash',
    rideId: 'ride_old',
  );

  RideRestoreCoordinator coordinator(
    Future<RideSnapshot?> Function() server, {
    List<Widget>? replaced,
    bool atRoot = true,
    Future<PendingCancel?> Function(String rideId)? pendingCancel,
  }) => RideRestoreCoordinator(
    resync: (_) async {},
    authRequired: () => false,
    serverActiveTrip: server,
    pendingCancel: pendingCancel ?? (_) async => null,
  )
    ..debugAtRoot = (() => atRoot)
    ..onReplaceRoot = replaced?.add;

  test('slow server at start: the ride opens even after the rider moved on '
      'to Where to', () async {
    final lookup = Completer<RideSnapshot?>();
    final replaced = <Widget>[];
    var atRoot = true;
    final restore = RideRestoreCoordinator(
      resync: (_) async {},
      authRequired: () => false,
      serverActiveTrip: () => lookup.future,
      pendingCancel: (_) async => null,
    )
      ..debugAtRoot = (() => atRoot)
      ..onReplaceRoot = replaced.add;
    expect(await restore.root(), isA<Home>());
    atRoot = false; // Where to / Select ride is on top of Home.
    lookup.complete(await serverTrip('ride_live', 'findingDriver'));
    await pumpEventQueue();
    expect(replaced.single, isA<FindingDrivers>());
    expect(restore.showing, RestoredSurface.finding);
  });

  test('a finished ride stored on the phone does not hide the live one on '
      'the server at start', () async {
    await RideSnapshotStore.save(stored(RideStatus.cancelledByRider));
    final restore = coordinator(() => serverTrip('ride_live', 'findingDriver'));
    final page = await restore.root();
    expect(page, isA<FindingDrivers>());
    expect((page as FindingDrivers).destinationAddress, 'Hamngatan 1');
    expect((await RideSnapshotStore.read())?.rideId, 'ride_live');
    expect(AppScope.instance.ride.rideId, 'ride_live');
  });

  test('a stale stored search gives way to the live trip on the server',
      () async {
    await RideSnapshotStore.save(
      stored(
        RideStatus.findingDriver,
        savedAt: DateTime.now().subtract(const Duration(hours: 1)),
      ),
    );
    final restore = coordinator(
      () => serverTrip('ride_live', 'driver_to_pickup'),
    );
    expect(await restore.root(), isA<WaitingForDriver>());
    expect((await RideSnapshotStore.read())?.rideId, 'ride_live');
  });

  test('back in the app on Home, the live trip on the server is shown',
      () async {
    final replaced = <Widget>[];
    final restore = coordinator(
      () => serverTrip('ride_live', 'findingDriver'),
      replaced: replaced,
    );
    expect(restore.showing, RestoredSurface.home);
    expect(await restore.resumeIfNeeded(), isA<FindingDrivers>());
    expect(replaced.single, isA<FindingDrivers>());
    expect(restore.showing, RestoredSurface.finding);
  });

  test('back in the app on Where to or Select ride, the live trip still '
      'replaces it', () async {
    final replaced = <Widget>[];
    final restore = coordinator(
      () => serverTrip('ride_live', 'findingDriver'),
      replaced: replaced,
      atRoot: false,
    );
    expect(await restore.resumeIfNeeded(), isA<FindingDrivers>());
    expect(replaced.single, isA<FindingDrivers>());
  });

  test('no live trip on the server: Home stays', () async {
    final replaced = <Widget>[];
    final restore = coordinator(() async => null, replaced: replaced);
    expect(await restore.resumeIfNeeded(), isNull);
    expect(replaced, isEmpty);
    expect(await restore.root(), isA<Home>());
  });

  test('a trip whose cancel is still on its way is not brought back',
      () async {
    final replaced = <Widget>[];
    final restore = coordinator(
      () => serverTrip('ride_live', 'findingDriver'),
      replaced: replaced,
      pendingCancel: (id) async => PendingCancel(rideId: id),
    );
    expect(await restore.resumeIfNeeded(), isNull);
    expect(replaced, isEmpty);
    expect(await RideSnapshotStore.read(), isNull);
  });

  test('a live search on the phone is never replaced', () async {
    await RideSnapshotStore.save(stored(RideStatus.findingDriver));
    var asked = 0;
    final restore = coordinator(() async {
      asked++;
      return serverTrip('ride_other', 'findingDriver');
    });
    expect(await restore.adoptServerActiveTrip(), isNull);
    expect(asked, 0);
    expect((await RideSnapshotStore.read())?.rideId, 'ride_old');
  });
}
