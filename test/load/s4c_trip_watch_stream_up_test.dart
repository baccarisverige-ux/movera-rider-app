import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/bootstrap.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/auth/token_store.dart';
import 'package:movera_rider/core/config/api_rider_config_repository.dart';
import 'package:movera_rider/features/ride_booking/application/rider_trip_watch.dart';

import '../contracts/contract_fixtures.dart';

/// S4c load cut (contract v0.18.145 `loadCut.riderTripWatch`): while
/// `/rider/config/stream` is connected the trip watch (Home's
/// GET /rider/trips/active, the booked-driver banner on a ride screen)
/// polls every 60 s instead of 8 s; rider_trip_changed and a reconnect
/// still read at once. When the stream drops the 8 s poll comes back.
/// Before the fix every Home and ride screen polled every 8 s whatever
/// the stream did (about 70 % of the requests in the S4b stress test).
void main() {
  List<int> secs(List<Duration> times) => [for (final t in times) t.inSeconds];

  test('the defaults are the contract numbers (8 s down, 60 s up)', () {
    final cut = contract['loadCut'] as Map<String, dynamic>;
    final seen = contract['bookedRideSeen'] as Map<String, dynamic>;
    final watch = RiderTripWatch(
      showsHome: () => true,
      adopt: () async {},
      bookedOnTheWay: () async => false,
      refreshBooked: () async {},
    );
    expect(watch.streamUpEvery.inSeconds, cut['riderTripWatchStreamUpSeconds']);
    expect(watch.streamUpEvery.inSeconds, 60);
    expect(watch.pollEvery.inSeconds, seen['pollSeconds']);
  });

  test('Home: stream up reads every 60 s, stream down back to 8 s', () {
    fakeAsync((async) {
      final reads = <Duration>[];
      final watch = RiderTripWatch(
        showsHome: () => true,
        adopt: () async => reads.add(async.elapsed),
        bookedOnTheWay: () async => false,
        refreshBooked: () async {},
      );
      watch.start();
      async.elapse(const Duration(seconds: 16));
      expect(secs(reads), [8, 16], reason: 'no stream yet: every 8 s');

      reads.clear();
      watch.onStreamUp(true);
      async.elapse(const Duration(seconds: 180));
      expect(secs(reads), [76, 136, 196], reason: 'stream up: every 60 s');

      reads.clear();
      watch.onStreamUp(false);
      async.elapse(const Duration(seconds: 24));
      expect(secs(reads), [204, 212, 220], reason: 'stream down: 8 s again');
      watch.stop();
    });
  });

  test('ride screen: the booked-driver banner read also slows to 60 s', () {
    fakeAsync((async) {
      final reads = <Duration>[];
      final watch = RiderTripWatch(
        showsHome: () => false,
        hasBooked: () => true,
        adopt: () async {},
        bookedOnTheWay: () async {
          reads.add(async.elapsed);
          return false;
        },
        refreshBooked: () async {},
      );
      watch.onStreamUp(true);
      watch.start();
      async.elapse(const Duration(seconds: 125));
      expect(secs(reads), [60, 120]);
      watch.stop();
    });
  });

  test('stream up: rider_trip_changed still reads at once', () {
    fakeAsync((async) {
      final reads = <Duration>[];
      final watch = RiderTripWatch(
        showsHome: () => true,
        adopt: () async => reads.add(async.elapsed),
        bookedOnTheWay: () async => false,
        refreshBooked: () async {},
      );
      watch.onStreamUp(true);
      watch.start();
      async.elapse(const Duration(seconds: 10));
      watch.onConfigEvent({'kind': 'rider_trip_changed'});
      async.flushMicrotasks();
      expect(secs(reads), [10]);
      watch.stop();
    });
  });

  test('stop and start keep the stream state (resume while up: 60 s)', () {
    fakeAsync((async) {
      final reads = <Duration>[];
      final watch = RiderTripWatch(
        showsHome: () => true,
        adopt: () async => reads.add(async.elapsed),
        bookedOnTheWay: () async => false,
        refreshBooked: () async {},
      );
      watch.onStreamUp(true);
      watch.start();
      watch.stop();
      watch.start();
      async.elapse(const Duration(seconds: 59));
      expect(reads, isEmpty);
      async.elapse(const Duration(seconds: 1));
      expect(secs(reads), [60]);
      watch.stop();
    });
  });

  test('the config stream tells up (an event) and down (the stream ends)', () {
    fakeAsync((async) {
      late StreamController<List<int>> body;
      final client = MockClient.streaming((request, _) async {
        if (request.url.path.endsWith('/stream')) {
          body = StreamController<List<int>>();
          return http.StreamedResponse(body.stream, 200);
        }
        return http.StreamedResponse(Stream.value(utf8.encode('{}')), 200);
      });
      final repo = ApiRiderConfigRepository(
        api: ApiClient(
          env: const AppEnv(
            flavor: AppFlavor.staging,
            apiBaseUrl: 'https://api.movera.invalid',
          ),
          client: client,
          tokens: MemoryTokenStore()..save(access: 'a', refresh: 'r'),
        ),
        cache: MemoryRiderConfigCache(),
        random: math.Random(7),
      );
      final states = <bool>[];
      repo.streamUpTaps.add(states.add);
      repo.watch('Z001');
      async.flushMicrotasks();
      expect(states, isEmpty, reason: 'a 200 alone is not connected (R3)');

      body.add(utf8.encode('data: {"kind":"heartbeat"}\n\n'));
      async.flushMicrotasks();
      expect(states, [true]);
      body.add(utf8.encode('data: {"kind":"heartbeat"}\n\n'));
      async.flushMicrotasks();
      expect(states, [true], reason: 'told once per change');

      unawaited(body.close());
      async.flushMicrotasks();
      expect(states, [true, false]);

      // Reconnected (5 s backoff) and up for 30 s without an event: up.
      async.elapse(const Duration(seconds: 6));
      async.elapse(const Duration(seconds: 30));
      expect(states, [true, false, true]);
      repo.dispose();
      async.flushMicrotasks();
      expect(states, [true, false, true, false]);
    });
  });

  test('the app wires the stream state into the trip watch', () {
    // The start-up wiring itself (bootstrap's wireTripWatch) on a real
    // settings stream: connected slows the reads to 60 s, dropped brings
    // the 8 s back.
    fakeAsync((async) {
      late StreamController<List<int>> body;
      final client = MockClient.streaming((request, _) async {
        if (request.url.path.endsWith('/stream')) {
          body = StreamController<List<int>>();
          return http.StreamedResponse(body.stream, 200);
        }
        return http.StreamedResponse(Stream.value(utf8.encode('{}')), 200);
      });
      final repo = ApiRiderConfigRepository(
        api: ApiClient(
          env: const AppEnv(
            flavor: AppFlavor.staging,
            apiBaseUrl: 'https://api.movera.invalid',
          ),
          client: client,
          tokens: MemoryTokenStore()..save(access: 'a', refresh: 'r'),
        ),
        cache: MemoryRiderConfigCache(),
        random: math.Random(7),
      );
      final reads = <Duration>[];
      final watch = RiderTripWatch(
        showsHome: () => true,
        adopt: () async => reads.add(async.elapsed),
        bookedOnTheWay: () async => false,
        refreshBooked: () async {},
      );

      wireTripWatch(repo, watch);
      repo.watch('Z001');
      async.elapse(const Duration(seconds: 16));
      expect(secs(reads), [8, 16], reason: 'started; not connected: 8 s');

      reads.clear();
      body.add(utf8.encode('data: {"kind":"heartbeat"}\n\n'));
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 120));
      expect(secs(reads), [76, 136], reason: 'connected: every 60 s');

      reads.clear();
      body.add(utf8.encode('data: {"kind":"rider_trip_changed"}\n\n'));
      async.flushMicrotasks();
      expect(secs(reads), [136], reason: 'a hint still reads at once');

      reads.clear();
      unawaited(body.close());
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 16));
      expect(secs(reads), [
        141,
        144,
        152,
      ], reason: 'stream down: 8 s again; the reconnect (5 s) reads at once');
      watch.stop();
      repo.dispose();
      async.flushMicrotasks();
    });
  });
}
