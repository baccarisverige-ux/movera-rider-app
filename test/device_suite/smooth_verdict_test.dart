import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/staging/smooth_verdict.dart';

/// Owner 2026-11-22: the Test Lab frame checks (SMOOTH) count on a profile
/// build; on a debug build a slow change is a WARN ("indicative (debug
/// build)") that never fails the run. Every other check stays strict.
///
/// Driver profile runs 45 and 46: the 20% limit alone failed a different
/// set each run, so on profile it is a WARN; FAIL is a frame over 200 ms
/// or more than 35% missed with at least 60 frames.
void main() {
  /// [missed] frames of 20 ms and the rest of 8 ms; [worst] replaces one.
  SmoothStats stats(int frames, int missed, {double? worst}) {
    final ms = <double>[
      for (var i = 0; i < frames; i++) i < missed ? 20.0 : 8.0,
    ];
    if (worst != null) ms[0] = worst;
    return SmoothStats.of(ms);
  }

  SmoothOutcome judge(SmoothStats s, String mode) =>
      SmoothVerdict.judge(s, mode: mode);

  group('frame numbers', () {
    test('frames, missed, worst, p90 and the jank budget', () {
      final s = SmoothStats.of([
        for (var i = 0; i < 8; i++) 10.0,
        26.667,
        116.667,
      ]);
      expect(s.frames, 10);
      expect(s.missed, 2);
      expect(s.worstMs, 116.667);
      // 9 of the 10 frames take at most 26.667 ms.
      expect(s.p90Ms, 26.667);
      // (26.667 - 16.667) + (116.667 - 16.667)
      expect(s.jankMs, closeTo(110.0, 1e-6));
      expect(s.ratio, 0.2);
    });

    test('no frames: all zero', () {
      final s = SmoothStats.of(const []);
      expect([s.frames, s.missed], [0, 0]);
      expect([s.worstMs, s.p90Ms, s.jankMs, s.ratio], [0, 0, 0, 0]);
    });

    test('one frame: it is the p90', () {
      expect(SmoothStats.of([30]).p90Ms, 30);
    });
  });

  group('profile and release build', () {
    test('run 46: over 20% with under 60 frames, or under 35%, is a WARN', () {
      for (final mode in ['profile', 'release']) {
        // waybill-during 10/48 = 21%, background-resume-2 15/68 = 22%,
        // end 13/42 = 31%.
        expect(judge(stats(48, 10), mode), SmoothOutcome.warn);
        expect(judge(stats(68, 15), mode), SmoothOutcome.warn);
        expect(judge(stats(42, 13), mode), SmoothOutcome.warn);
      }
    });

    test('run 45 / 46 rows at or under 20% pass', () {
      // background-resume-2 run 45: 15/82 = 18%; exactly 20% is not over.
      expect(judge(stats(82, 15), 'profile'), SmoothOutcome.pass);
      expect(judge(stats(50, 10), 'profile'), SmoothOutcome.pass);
      expect(judge(stats(0, 0), 'profile'), SmoothOutcome.pass);
    });

    test('over 35% with at least 60 frames is a FAIL', () {
      expect(judge(stats(100, 40), 'profile'), SmoothOutcome.fail);
      expect(judge(stats(60, 22), 'profile'), SmoothOutcome.fail);
      // Exactly 35% is not over; 59 frames are too few to fail.
      expect(judge(stats(100, 35), 'profile'), SmoothOutcome.warn);
      expect(judge(stats(59, 40), 'profile'), SmoothOutcome.warn);
      // Any frame count warns over 20%.
      expect(judge(stats(3, 1), 'profile'), SmoothOutcome.warn);
    });

    test('a frame over 200 ms is a FAIL at any frame count', () {
      expect(judge(stats(5, 0, worst: 250), 'profile'), SmoothOutcome.fail);
      expect(judge(stats(80, 0, worst: 200.1), 'release'), SmoothOutcome.fail);
      // 102 ms (the worst of runs 45 and 46) and exactly 200 ms are not.
      expect(judge(stats(80, 0, worst: 102), 'profile'), SmoothOutcome.pass);
      expect(judge(stats(80, 0, worst: 200), 'profile'), SmoothOutcome.pass);
    });

    test('an unknown mode is judged as profile, never as debug', () {
      expect(judge(stats(100, 40), 'other'), SmoothOutcome.fail);
    });

    test('a WARN says it is over the warn limit', () {
      expect(
        SmoothVerdict.detail(SmoothOutcome.warn, 'frames=48', mode: 'profile'),
        'over the warn limit (not a FAIL): frames=48',
      );
      expect(
        SmoothVerdict.detail(SmoothOutcome.fail, 'frames=48', mode: 'profile'),
        'frames=48',
      );
    });
  });

  group('debug build: as before, every miss is a WARN', () {
    test('a freeze or over 20% with at least 10 frames', () {
      expect(judge(stats(5, 0, worst: 250), 'debug'), SmoothOutcome.warn);
      expect(judge(stats(100, 40), 'debug'), SmoothOutcome.warn);
      expect(judge(stats(40, 12), 'debug'), SmoothOutcome.warn);
      expect(
        SmoothVerdict.detail(SmoothOutcome.warn, 'frames=40', mode: 'debug'),
        'indicative (debug build): frames=40',
      );
    });

    test('a smooth change, or under 10 frames, passes', () {
      expect(judge(stats(40, 8), 'debug'), SmoothOutcome.pass);
      expect(judge(stats(9, 9), 'debug'), SmoothOutcome.pass);
    });
  });

  test('the build line the summary tool reads', () {
    expect(SmoothVerdict.buildLine('profile'), 'BUILD mode=profile');
    // `flutter test` runs debug code: the default is the real build.
    expect(SmoothVerdict.buildMode, 'debug');
    expect(SmoothVerdict.buildLine(), 'BUILD mode=debug');
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
      expect(watch, contains('SmoothVerdict.judge(stats)'));
      expect(watch, contains("log.smooth('TRANSITION:\$name:SMOOTH',outcome,"));
    });

    test('the rows carry the outcome, p90 and the jank budget', () {
      expect(watch, contains("'smoothOutcome':outcome.name"));
      expect(watch, contains("'p90Ms':"));
      expect(watch, contains("'jankMs':"));
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
