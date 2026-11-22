import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/api_reservation_repository.dart';

/// Test Lab run 39: the booked list (`GET /rider/trips?kind=scheduled`) was
/// read 2-5 times within 4 s: several `rider_trip_changed` events in a row
/// (a call: ringing, answered, ended), and a resume that reads on start and
/// again when the stream reconnects. `refresh()` only joined a read still
/// out. Now a call within 5 s of the last read's end waits for ONE trailing
/// read at the end of that window.
void main() {
  const staging = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://api.example.test',
  );
  const window = ReservationController.refreshQuiet;

  /// Runs [body] with a controller whose clock is the fake one; [reads]
  /// holds when each list read started.
  void run(
    void Function(
      FakeAsync async,
      ReservationController reservations,
      List<Duration> reads,
    )
    body, {
    Duration readTakes = Duration.zero,
  }) {
    fakeAsync((async) {
      final start = DateTime.utc(2026, 11, 22, 10);
      final reads = <Duration>[];
      final reservations = ReservationController(
        store: ApiReservationRepository(
          api: ApiClient(
            client: MockClient((request) async {
              reads.add(async.elapsed);
              if (readTakes > Duration.zero) {
                await Future<void>.delayed(readTakes);
              }
              return http.Response(
                jsonEncode({'items': <Object>[], 'nextCursor': null}),
                200,
                headers: {'content-type': 'application/json'},
              );
            }),
            env: staging,
          ),
        ),
        environment: staging,
        clock: () => start.add(async.elapsed),
      );
      body(async, reservations, reads);
      reservations.dispose();
    });
  }

  test('the window is 5 s', () => expect(window.inSeconds, 5));

  test('three calls in a burst: one read now, one trailing read', () {
    run((async, reservations, reads) {
      for (var i = 0; i < 3; i++) {
        reservations.refresh(); // rider_trip_changed
        async.elapse(const Duration(milliseconds: 300));
      }
      expect(reads, hasLength(1));
      async.elapse(window);
      expect(reads, hasLength(2), reason: 'the later hints are not lost');
      expect(reads[1] - reads[0], greaterThanOrEqualTo(window));
      async.elapse(const Duration(minutes: 1));
      expect(reads, hasLength(2), reason: 'one trailing read, no more');
    });
  });

  test('resume (start, then the stream reconnects): two reads at most, '
      '5 s or more apart', () {
    run((async, reservations, reads) {
      reservations.refresh(); // RiderTripWatch.start
      async.elapse(const Duration(milliseconds: 800));
      reservations.refresh(); // onStreamReconnected
      async.elapse(const Duration(seconds: 4));
      expect(reads, hasLength(1), reason: 'nothing repeats within 4 s');
      async.elapse(const Duration(seconds: 30));
      expect(reads, hasLength(2));
      expect(reads[1] - reads[0], greaterThanOrEqualTo(window));
    });
  });

  test('a call after the window reads at once', () {
    run((async, reservations, reads) {
      reservations.refresh();
      async.elapse(window + const Duration(milliseconds: 100));
      expect(reads, hasLength(1));
      reservations.refresh();
      async.flushMicrotasks();
      expect(reads, hasLength(2));
      async.elapse(const Duration(minutes: 1));
      expect(reads, hasLength(2));
    });
  });

  test('a call in the window completes after the trailing read', () {
    run((async, reservations, reads) {
      reservations.refresh();
      async.elapse(const Duration(seconds: 1));
      var done = false;
      reservations.refresh().then((_) => done = true);
      async.elapse(const Duration(seconds: 3));
      expect(done, isFalse, reason: 'not answered by the read before it');
      expect(reads, hasLength(1));
      async.elapse(const Duration(seconds: 2));
      expect(reads, hasLength(2));
      expect(done, isTrue);
    });
  });

  test('now: true reads at once and answers the calls waiting', () {
    run((async, reservations, reads) {
      reservations.refresh();
      async.elapse(const Duration(seconds: 1));
      var waited = false;
      reservations.refresh().then((_) => waited = true);
      var done = false;
      reservations.refresh(now: true).then((_) => done = true);
      async.flushMicrotasks();
      expect(reads, hasLength(2));
      expect(done, isTrue);
      expect(waited, isTrue, reason: 'that read started after its call');
      async.elapse(const Duration(minutes: 1));
      expect(reads, hasLength(2), reason: 'no trailing read is left over');
    });
  });

  group('a call while a read is out (the read may be older than the hint)', () {
    const slow = Duration(seconds: 2);

    test('a hint gives exactly one more read after it, and is answered by '
        'that read', () {
      run(readTakes: slow, (async, reservations, reads) {
        reservations.refresh();
        async.elapse(const Duration(seconds: 1));
        var done = false;
        reservations.refresh().then((_) => done = true); // the hint
        async.elapse(const Duration(seconds: 2)); // the first read ended at 2 s
        expect(reads, hasLength(1));
        expect(done, isFalse, reason: 'the read out started before the hint');
        async.elapse(window); // 8 s: the trailing read started at 7 s
        expect(reads, hasLength(2));
        expect(reads[1], slow + window);
        expect(done, isFalse, reason: 'the trailing read is still out');
        async.elapse(slow);
        expect(done, isTrue);
        async.elapse(const Duration(minutes: 1));
        expect(reads, hasLength(2));
      });
    });

    test('now: true gives a second read right after the first one ends, '
        'never two at once', () {
      run(readTakes: slow, (async, reservations, reads) {
        reservations.refresh();
        async.elapse(const Duration(seconds: 1));
        var done = false;
        reservations.refresh(now: true).then((_) => done = true);
        async.elapse(const Duration(milliseconds: 900));
        expect(reads, hasLength(1), reason: 'not in parallel');
        async.elapse(const Duration(milliseconds: 200));
        expect(reads, hasLength(2));
        expect(reads[1], slow, reason: 'right when the first one ended');
        expect(done, isFalse);
        async.elapse(slow);
        expect(done, isTrue);
        async.elapse(const Duration(minutes: 1));
        expect(reads, hasLength(2));
      });
    });

    test('a burst that spans the read ends with exactly one trailing read', () {
      run(readTakes: slow, (async, reservations, reads) {
        var answered = 0;
        reservations.refresh(); // 0 s, reads
        for (var i = 0; i < 5; i++) {
          // 0.5 s .. 4.5 s: three while the read is out, two after it.
          async.elapse(const Duration(milliseconds: 500));
          if (i.isOdd) async.elapse(const Duration(milliseconds: 500));
          reservations.refresh().then((_) => answered++);
          async.elapse(const Duration(milliseconds: 500));
        }
        expect(reads, hasLength(1));
        async.elapse(const Duration(minutes: 1));
        expect(reads, hasLength(2));
        expect(reads[1], slow + window);
        expect(answered, 5);
      });
    });
  });
}
