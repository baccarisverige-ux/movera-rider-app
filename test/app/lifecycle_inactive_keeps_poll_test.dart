import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/app/lifecycle/app_lifecycle.dart';
import 'package:movera_rider/features/ride_booking/application/rider_trip_watch.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Supervisor S5 / owner 2026-11-07: on the web a blur (tab switch, a
/// browser dialog) is `inactive`, often with no `resumed` after it. The
/// Home poll that opens a booked ride must survive it; only hidden /
/// paused / detached stop it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('S1: inactive (web blur) without resumed keeps the Home poll', () {
    fakeAsync((async) {
      final w = RiderTripWatch.instance;
      w.start();
      expect(w.polling, isTrue);
      AppLifecycleObserver().didChangeAppLifecycleState(
        AppLifecycleState.inactive,
      );
      async.flushMicrotasks();
      expect(
        w.polling,
        isTrue,
        reason: 'Home poll must survive a blur (inactive)',
      );
      w.stop();
    });
  });

  for (final state in [
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.detached,
  ]) {
    test('${state.name} still stops the Home poll', () {
      fakeAsync((async) {
        final w = RiderTripWatch.instance;
        w.start();
        AppLifecycleObserver().didChangeAppLifecycleState(state);
        async.flushMicrotasks();
        expect(w.polling, isFalse);
        w.stop();
      });
    });
  }
}
