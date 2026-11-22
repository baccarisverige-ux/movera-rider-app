import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/staging/smooth_verdict.dart';

/// Owner 2026-11-22: the Test Lab frame checks (SMOOTH) count on a profile
/// build; on a debug build a slow frame is a WARN ("indicative (debug
/// build)") that never fails the run. Every other check stays strict.
void main() {
  group('SMOOTH verdict by build mode', () {
    test('a smooth change passes in every build mode', () {
      for (final mode in ['debug', 'profile', 'release']) {
        expect(
          SmoothVerdict.judge(smooth: true, mode: mode),
          SmoothOutcome.pass,
        );
      }
    });

    test('debug: a slow frame is a WARN, said as indicative', () {
      final outcome = SmoothVerdict.judge(smooth: false, mode: 'debug');
      expect(outcome, SmoothOutcome.warn);
      expect(
        SmoothVerdict.detail(outcome, 'frames=40 worst=410.0 ms'),
        'indicative (debug build): frames=40 worst=410.0 ms',
      );
    });

    test('profile and release: a slow frame is a FAIL, detail unchanged', () {
      for (final mode in ['profile', 'release']) {
        final outcome = SmoothVerdict.judge(smooth: false, mode: mode);
        expect(outcome, SmoothOutcome.fail);
        expect(SmoothVerdict.detail(outcome, 'frames=40'), 'frames=40');
      }
    });

    test('an unknown mode is strict (FAIL), never a WARN', () {
      expect(
        SmoothVerdict.judge(smooth: false, mode: 'other'),
        SmoothOutcome.fail,
      );
    });

    test('the build line the summary tool reads', () {
      expect(SmoothVerdict.buildLine('profile'), 'BUILD mode=profile');
      // `flutter test` runs debug code: the default is the real build.
      expect(SmoothVerdict.buildMode, 'debug');
      expect(SmoothVerdict.buildLine(), 'BUILD mode=debug');
    });
  });

  group('the harness uses it for SMOOTH only', () {
    // Without white space: the formatter may break a line anywhere.
    String flat(String text) => text.replaceAll(RegExp(r'\s+'), '');
    final watch = flat(
      File('integration_test/staging/transition_watch.dart').readAsStringSync(),
    );
    final log = flat(
      File('integration_test/staging/check_log.dart').readAsStringSync(),
    );

    test('SMOOTH goes through the build-mode verdict', () {
      expect(watch, contains("log.smooth('TRANSITION:\$name:SMOOTH',smooth,"));
      expect(log, contains('SmoothVerdict.judge(smooth:ok,mode:mode)'));
    });

    test('RELOAD and ERRORS stay PASS / FAIL', () {
      expect(watch, contains("check('RELOAD',reloadOk"));
      expect(watch, contains("check('ERRORS',errorsOk"));
      expect(watch, isNot(contains("check('SMOOTH'")));
      expect(
        watch,
        contains('ok?log.pass(id,title,detail):log.fail(id,title,detail)'),
      );
    });

    test('a WARN is not a failure, and the build is said at the start', () {
      expect(log, contains('results.where((r)=>r.outcome==CheckOutcome.fail)'));
      expect(log, contains('say(SmoothVerdict.buildLine())'));
      expect(
        log,
        contains("'skipped=\${skipped.length}warned=\${warned.length}'"),
      );
    });
  });
}
