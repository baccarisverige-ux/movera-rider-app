import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/app/lifecycle/app_lifecycle.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/realtime/api_ride_realtime.dart';
import 'package:movera_rider/core/realtime/realtime_connection.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Audit app-lifecycle 2026-11-20 P8: the trip poll ran every 10 s for
/// hours while the app was in the background. In the background it slows
/// to [ApiRideRealtime.backgroundPollInterval]; on resume it reads the trip
/// at once and goes back to the normal pace. Pushes are untouched.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));
  const live = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://x.invalid',
  );
  final t0 = DateTime.utc(2026, 11, 20, 9);

  test('paused slows the poll; resumed reads at once and speeds up', () {
    fakeAsync((async) {
      var now = t0;
      var calls = 0;
      final rt = ApiRideRealtime(
        api: ApiClient(
          client: MockClient((_) async {
            calls++;
            return http.Response(
              jsonEncode({
                'tripId': 'trp_1',
                'status': 'searching',
                'version': 1,
                'updatedAt': t0.toIso8601String(),
              }),
              200,
            );
          }),
          env: live,
        ),
        connection: RealtimeConnection(),
        clock: () => now,
        followStream: false,
      );
      void tick(Duration d) {
        now = now.add(d);
        async.elapse(d);
      }

      final sub = rt.subscribe('trp_1').listen((_) {});
      async.flushMicrotasks();
      tick(const Duration(minutes: 1));
      final foreground = calls;
      expect(foreground, inInclusiveRange(6, 8));

      AppLifecycleObserver().didChangeAppLifecycleState(
        AppLifecycleState.paused,
      );
      async.flushMicrotasks();
      final before = calls;
      tick(const Duration(hours: 1));
      final background = calls - before;
      expect(
        background,
        lessThanOrEqualTo(61),
        reason: 'one hour in the background polled $background times',
      );
      expect(background, greaterThan(0), reason: 'never stopped entirely');

      AppLifecycleObserver().didChangeAppLifecycleState(
        AppLifecycleState.inactive,
      );
      async.flushMicrotasks();
      final atInactive = calls;
      tick(const Duration(seconds: 30));
      expect(
        calls - atInactive,
        lessThanOrEqualTo(1),
        reason: 'inactive alone does not speed it up',
      );

      final atResume = calls;
      AppLifecycleObserver().didChangeAppLifecycleState(
        AppLifecycleState.resumed,
      );
      async.flushMicrotasks();
      expect(calls, atResume + 1, reason: 'resume reads the trip at once');
      tick(const Duration(seconds: 30));
      expect(calls - atResume, inInclusiveRange(3, 5));

      sub.cancel();
      rt.dispose();
    });
  });
}
