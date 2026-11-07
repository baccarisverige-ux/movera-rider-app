import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/ride_booking/application/ride_restore_coordinator.dart';
import 'package:movera_rider/features/ride_booking/data/active_trip_repositories.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Owner 2026-11-07 ("Yes, build it"): booked ride stuck on Home.
///
/// SUPERVISOR 1, staging log 2026-11-07 15:36:39 UTC (owner video 16:37):
/// the rider app came back to the front just after the booked driver
/// started; GET /rider/trips/active answered 200 TWICE, 21 ms apart (the
/// lifecycle resume and the RiderTripWatch check / rider_trip_changed), the
/// rider never opened the trip (no GET /trips/{id}/events), stayed on Home,
/// and from then on only polled GET /rider/trips (the watch's "a ride is on
/// screen" branch).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  test('two resumes at once on Home: the booked ride stays on screen and '
      '`showing` matches what is on screen', () async {
    final answers = [Completer<void>(), Completer<void>()];
    var calls = 0;
    final repo = ApiActiveTripRepository(
      api: ApiClient(
        env: const AppEnv(
          flavor: AppFlavor.staging,
          apiBaseUrl: 'https://api.example.test',
        ),
        client: MockClient((_) async {
          await answers[calls++].future;
          return http.Response(
            File(
              'test/ride/fixtures/active_trip_driver_to_pickup.json',
            ).readAsStringSync(),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );
    final shown = <Widget>[];
    final restore =
        RideRestoreCoordinator(
            resync: (_) async {},
            authRequired: () => false,
            serverActiveTrip: repo.fetchActive,
            pendingCancel: (_) async => null,
          )
          ..debugAtRoot = (() => true)
          ..onReplaceRoot = shown.add;
    // AppLifecycleObserver.resumed -> resumeIfNeeded, and RiderTripWatch
    // check (rider_trip_changed / poll) -> resumeIfNeeded, in the same turn.
    final a = restore.resumeIfNeeded();
    final b = restore.resumeIfNeeded();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    // Staging: the two answers came back 21 ms apart (15:36:39.781 / .802).
    answers[0].complete();
    await Future<void>.delayed(const Duration(milliseconds: 21));
    answers[1].complete();
    await Future.wait([a, b]);
    expect(shown, isNotEmpty);
    expect(
      shown.last,
      isA<WaitingForDriver>(),
      reason:
          'root seen by the rider after both resumes: ${shown.map((w) => w.runtimeType).toList()}',
    );
    expect(restore.showing, RestoredSurface.waiting);
  });

  test('Home placed by resume always resets `showing`, so the next watch '
      'tick opens the booked ride (self-heal)', () async {
    var driverStarted = false;
    final repo = ApiActiveTripRepository(
      api: ApiClient(
        env: const AppEnv(
          flavor: AppFlavor.staging,
          apiBaseUrl: 'https://api.example.test',
        ),
        client: MockClient(
          (_) async => http.Response(
            File(
              'test/ride/fixtures/active_trip_driver_to_pickup.json',
            ).readAsStringSync(),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      ),
    );
    final shown = <Widget>[];
    final restore =
        RideRestoreCoordinator(
            resync: (_) async {},
            authRequired: () => false,
            // No active trip on the server until the booked driver starts.
            serverActiveTrip: () async =>
                driverStarted ? await repo.fetchActive() : null,
            pendingCancel: (_) async => null,
          )
          ..debugAtRoot = (() => true)
          ..onReplaceRoot = shown.add
          // State left behind by the race: the coordinator believes a ride is
          // on screen while nothing is stored on this device.
          ..showing = RestoredSurface.waiting;
    await restore.resumeIfNeeded();
    expect(shown.map((w) => w.runtimeType).toList(), isNot(isEmpty));
    expect(shown.last, isNot(isA<WaitingForDriver>()));
    expect(
      restore.showing,
      RestoredSurface.home,
      reason: 'Home is on screen, so `showing` must say home',
    );
    // RiderTripWatch's next 8 s tick, after the booked driver started.
    driverStarted = true;
    await restore.resumeIfNeeded();
    expect(
      shown.last,
      isA<WaitingForDriver>(),
      reason: 'roots seen: ${shown.map((w) => w.runtimeType).toList()}',
    );
    expect(restore.showing, RestoredSurface.waiting);
  });
}
