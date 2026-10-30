import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/home/application/home_presence.dart';

/// Live test 2026-10-30 (contract v0.18.4 `driverHome.ridersOnline`): a
/// rider with the app open on Home must be counted online. The server
/// counts the riders who ask for the cars near them; Home now asks while it
/// is on screen and the rider is signed in.
void main() {
  const stockholm = GeoPoint(59.3326, 18.0649);

  test('on screen and signed in: asks at once, then every 45 s, inside the '
      'server\'s 120 s window', () {
    fakeAsync((time) {
      final asked = <GeoPoint>[];
      final presence = HomePresence(
        ping: (point) async => asked.add(point),
        position: () => stockholm,
        signedIn: () async => true,
      );
      presence.start();
      time.flushMicrotasks();
      expect(asked, [stockholm]);
      time.elapse(const Duration(seconds: 44));
      expect(asked, hasLength(1));
      time.elapse(const Duration(seconds: 1));
      expect(asked, hasLength(2));
      time.elapse(const Duration(minutes: 3));
      expect(asked, hasLength(6));
      expect(HomePresence.defaultEvery.inSeconds, lessThan(120));
      presence.dispose();
    });
  });

  test('covered, in the background or closed: nothing more is asked', () {
    fakeAsync((time) {
      var asked = 0;
      final presence = HomePresence(
        ping: (_) async => asked++,
        position: () => stockholm,
        signedIn: () async => true,
      );
      presence.start();
      time.flushMicrotasks();
      presence.stop();
      time.elapse(const Duration(minutes: 5));
      expect(asked, 1);
      presence.start();
      time.flushMicrotasks();
      expect(asked, 2, reason: 'back on screen: asked again at once');
      presence.dispose();
      time.elapse(const Duration(minutes: 5));
      expect(asked, 2);
    });
  });

  test('signed out (or the demo): the server is never asked', () {
    fakeAsync((time) {
      var asked = 0;
      final presence = HomePresence(
        ping: (_) async => asked++,
        position: () => stockholm,
        signedIn: () async => false,
      );
      presence.start();
      time.elapse(const Duration(minutes: 5));
      expect(asked, 0);
      presence.dispose();
    });
  });

  test('no position yet: asked as soon as there is one; a failed call is '
      'tried again at the next tick', () {
    fakeAsync((time) {
      GeoPoint? at;
      var calls = 0;
      final presence = HomePresence(
        ping: (_) async {
          calls++;
          if (calls == 1) throw StateError('offline');
        },
        position: () => at,
        signedIn: () async => true,
      );
      presence.start();
      time.elapse(const Duration(seconds: 4));
      expect(calls, 0);
      at = stockholm;
      time.elapse(const Duration(seconds: 1));
      expect(calls, 1);
      time.elapse(HomePresence.defaultEvery);
      expect(calls, 2);
      presence.dispose();
    });
  });
}
