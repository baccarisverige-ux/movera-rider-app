import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/features/ride_booking/application/rider_trip_watch.dart';

/// R4 (fix plan 2026-11-13; owner 12:23 UTC "32 s (Rec.)"; contract
/// v0.18.83 `bookedRideSeen.pollBackoff`): Home reads
/// GET /rider/trips/active every 8 s. That read is never shed, so under
/// load it waits in the busy pool and answers 503 server_busy. Before the
/// fix the poll kept its 8 s whatever the answer.
///
/// Contract rule: after a failed read the next waits 16 s, after a second
/// failure 32 s, and stays at 32 s (the cap); never shorter than
/// Retry-After; the first answer goes back to every 8 s; a
/// rider_trip_changed hint still reads at once.
void main() {
  const busy = ApiError(
    code: 'unavailable',
    reason: 'server_busy',
    message: 'busy',
    statusCode: 503,
    retryAfter: Duration(seconds: 2),
  );

  /// The gaps in seconds between the reads at [times].
  List<int> gaps(List<Duration> times) => [
    for (var i = 1; i < times.length; i++) (times[i] - times[i - 1]).inSeconds,
  ];

  test('a failing server: reads 16 s, then 32 s apart, and stay at 32 s '
      '(the cap); the first answer brings back 8 s', () {
    fakeAsync((async) {
      final reads = <Duration>[];
      var failing = true;
      final watch = RiderTripWatch(
        showsHome: () => true,
        adopt: () async {
          reads.add(async.elapsed);
          if (failing) throw busy;
        },
        bookedOnTheWay: () async => false,
        refreshBooked: () async {},
      );
      watch.start();
      async.elapse(const Duration(minutes: 4));
      // Before the fix: 240 / 8 = 30 reads of a server that is down.
      expect(gaps(reads), [16, 32, 32, 32, 32, 32, 32]);
      expect(reads, hasLength(8));

      // The server answers again (at 240 s): the read that ends the pause
      // (216 + 32 = 248 s) answers, then every 8 s.
      failing = false;
      reads.clear();
      async.elapse(const Duration(seconds: 8));
      expect(reads.map((t) => t.inSeconds), [248]);
      reads.clear();
      async.elapse(const Duration(seconds: 40));
      expect(gaps(reads), [8, 8, 8, 8]);
      expect(reads, hasLength(5));
      watch.stop();
    });
  });

  test('one failure then an answer: back to 8 s at once', () {
    fakeAsync((async) {
      final reads = <Duration>[];
      var fails = 1;
      final watch = RiderTripWatch(
        showsHome: () => true,
        adopt: () async {
          reads.add(async.elapsed);
          if (fails-- > 0) throw busy;
        },
        bookedOnTheWay: () async => false,
        refreshBooked: () async {},
      );
      watch.start();
      async.elapse(const Duration(seconds: 60));
      // 8 (fails) → 24 (answers) → 32, 40, 48, 56.
      expect(reads.map((t) => t.inSeconds), [8, 24, 32, 40, 48, 56]);
      watch.stop();
    });
  });

  test('a wait is never shorter than Retry-After', () {
    fakeAsync((async) {
      final reads = <Duration>[];
      final watch = RiderTripWatch(
        showsHome: () => true,
        adopt: () async {
          reads.add(async.elapsed);
          throw const ApiError(
            code: 'rate_limited',
            message: 'slow down',
            statusCode: 429,
            retryAfter: Duration(seconds: 45),
          );
        },
        bookedOnTheWay: () async => false,
        refreshBooked: () async {},
      );
      watch.start();
      async.elapse(const Duration(seconds: 130));
      // 8 → (≥ 45 s, on the 8 s ticks) 56 → 104.
      expect(reads.map((t) => t.inSeconds), [8, 56, 104]);
      watch.stop();
    });
  });

  test('a rider_trip_changed hint is read at once, even in a pause', () {
    fakeAsync((async) {
      var calls = 0;
      final watch = RiderTripWatch(
        showsHome: () => true,
        adopt: () async {
          calls++;
          throw busy;
        },
        bookedOnTheWay: () async => false,
        refreshBooked: () async {},
      );
      watch.start();
      async.elapse(const Duration(seconds: 9));
      final before = calls;
      watch.onConfigEvent({'kind': 'rider_trip_changed'});
      async.flushMicrotasks();
      expect(calls, before + 1);
      watch.stop();
    });
  });

  test('back in front after a pause: the next 8 s tick reads again', () {
    fakeAsync((async) {
      final reads = <Duration>[];
      var failing = true;
      final watch = RiderTripWatch(
        showsHome: () => true,
        adopt: () async {
          reads.add(async.elapsed);
          if (failing) throw busy;
        },
        bookedOnTheWay: () async => false,
        refreshBooked: () async {},
      );
      watch.start();
      async.elapse(const Duration(seconds: 60));
      // 8, 24, 56: now in a 32 s pause.
      expect(reads.map((t) => t.inSeconds), [8, 24, 56]);
      watch.stop();
      failing = false;
      async.elapse(const Duration(seconds: 2));
      watch.start();
      async.elapse(const Duration(seconds: 17));
      // 62 + 8 = 70, then every 8 s (the answer reset the backoff).
      expect(reads.map((t) => t.inSeconds), [8, 24, 56, 70, 78]);
      watch.stop();
    });
  });
}
