import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/common.dart';
import 'package:integration_test/integration_test.dart';
import 'package:movera_rider/app/config/env.dart';

import 'staging/check_log.dart';
import 'staging/rider_session.dart';
import 'staging/trip_run.dart';

/// G31 rider (owner 2026-11-12: "then the RIDER app on phone (driver via
/// API) with the same checks"; "Also the schedule ride"): one whole trip on
/// a real Firebase Test Lab phone against staging. The rider app runs on
/// the phone (big-test rider se.r35, fallback se.r36); the driver is
/// played over HTTP by the test (big-test driver se.d38, the same pair as
/// the driver app's suite, which never runs at the same time: shared
/// workflow concurrency group).
///
/// Live scenario (testlab_test `trip-lifecycle`): START, SIGN-IN,
/// DRIVER-SIGN-IN, DRIVER-ONLINE, SOS-ZONES, BOOK, SEARCHING, SOS-FINDING,
/// DRIVER-FOUND, ARRIVING, SWITCH-1, ARRIVED, PIN, PAY-IN-CAR, CHAT,
/// CALL-OUT, CALL-IN, SWITCH-2, SOS, RIDE-CHECK, DROPOFF, PAY (G33 line =
/// the driver's cashDue), RATE, RECEIPT, HISTORY, CLEANUP, OFFLINE, and
/// for every screen change `TRANSITION:<name>:SMOOTH` / RELOAD / ERRORS.
///
/// Booked scenario (`trip-scheduled`, MOVERA_TL_SCENARIO=scheduled):
/// SCHED-CANCEL-BOOK, SCHED-CANCEL-ACCEPT, SCHED-CANCEL, SCHED-BOOK,
/// SCHED-ACCEPT, SCHED-LIST, SCHED-REMINDER, SCHED-LEAVE, then the trip
/// steps without chat / calls / SOS / ride check.
///
/// Numbers and the code come ONLY at run time (MainActivityTest copies the
/// instrumentation arguments into this process's environment); nothing is
/// built into the APK (test/auth/a12_no_test_numbers_test.dart). They are
/// never printed.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Real frames at the display's pace (the frame checks measure them).
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  final phone = tlEnv('MOVERA_TL_PHONE');
  final code = tlEnv('MOVERA_TL_CODE');
  final peerPhone = tlEnv('MOVERA_TL_PEER_PHONE');
  final scheduled = tlEnv('MOVERA_TL_SCENARIO') == 'scheduled';
  final live =
      AppEnv.current.authRequired && AppEnv.current.flavor == AppFlavor.staging;
  final name = scheduled
      ? 'rider booked ride lifecycle'
      : 'rider trip lifecycle';

  // Driver suite run 6: a test that times out (or hangs) is recorded
  // nowhere by the integration_test binding (JUnit "OK (0 tests)", Test
  // Lab "Passed"). Tear-downs run last-in-first-out, so this one runs
  // before the binding's own `allTestsFinished`: JUnit then shows 1 test,
  // 1 failure.
  var bodyDone = false;
  var bodyStarted = false;
  tearDownAll(() {
    if (bodyStarted && !bodyDone && binding.results[name] is! Failure) {
      binding.results[name] = Failure(
        name,
        'test body did not finish (timeout or hang)',
      );
    }
  });

  final String? skipReason = !live
      ? 'not a live staging build (MOVERA_FLAVOR=staging and '
            'MOVERA_AUTH_REQUIRED=true are needed)'
      : phone == null || code == null || peerPhone == null
      ? 'no test rider / driver number at run time (the workflow passes '
            'them from the MOVERA_TEST_NUMBERS secret)'
      : null;

  if (skipReason != null) {
    testWidgets('trip lifecycle SKIPPED: $skipReason', (tester) async {
      CheckLog.say('SKIP all checks: $skipReason');
    });
    return;
  }

  testWidgets(
    name,
    (tester) async {
      bodyStarted = true;
      final log = CheckLog(
        binding: binding,
        outDir: tlEnv('MOVERA_TL_OUT'),
        shots: tlEnv('MOVERA_TL_SHOTS') != '0',
      );
      final run = TripRun(tester, log, scheduled: scheduled);
      try {
        await run.all(phone: phone!, code: code!, peerPhone: peerPhone!);
      } finally {
        // SUMMARY / SUMMARY-JSON / summary.json, then the END line (once:
        // the watchdog may have written them already).
        await run.writeResults();
        // bootstrap() replaced the error handlers: the test's own back.
        run.restoreHandlers();
      }
      final failed = log.failures;
      expect(
        failed,
        isEmpty,
        reason: [
          for (final f in failed) '${f.id} (${f.title}): ${f.detail}',
        ].join('\n'),
      );
      bodyDone = true;
    },
    // Hard stop 15 min -> watchdog 15 min 45 s -> clean-up done by about
    // 17 min 30 s -> this test timeout 18 min (TripRun.testLimit) -> Test
    // Lab --timeout 25 min (android-test-apk.yml; install and start count
    // too).
    timeout: const Timeout(TripRun.testLimit),
  );
}
