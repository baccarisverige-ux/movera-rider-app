import 'package:flutter/foundation.dart' show kDebugMode, kProfileMode;

/// How a frame check (`TRANSITION:<name>:SMOOTH`) ends.
enum SmoothOutcome { pass, warn, fail }

/// The frame numbers of one screen change. One value per frame: the
/// longer of its build and raster time, in ms.
class SmoothStats {
  const SmoothStats({
    required this.frames,
    required this.missed,
    required this.worstMs,
    required this.p90Ms,
    required this.jankMs,
  });

  factory SmoothStats.of(List<double> frameMs) {
    if (frameMs.isEmpty) {
      return const SmoothStats(
        frames: 0,
        missed: 0,
        worstMs: 0,
        p90Ms: 0,
        jankMs: 0,
      );
    }
    final sorted = [...frameMs]..sort();
    var missed = 0;
    var jank = 0.0;
    for (final ms in sorted) {
      if (ms > SmoothVerdict.budgetMs) {
        missed++;
        jank += ms - SmoothVerdict.budgetMs;
      }
    }
    // Nearest rank: the smallest value with 90% of the frames at or under it.
    final rank = (sorted.length * 0.9).ceil().clamp(1, sorted.length);
    return SmoothStats(
      frames: sorted.length,
      missed: missed,
      worstMs: sorted.last,
      p90Ms: sorted[rank - 1],
      jankMs: jank,
    );
  }

  final int frames;

  /// Frames over the 16.7 ms budget.
  final int missed;
  final double worstMs;

  /// 90% of the frames took at most this long. Logged only (not judged).
  final double p90Ms;

  /// The jank budget: the sum of (frame ms - 16.7) over the missed
  /// frames. Logged only (not judged).
  final double jankMs;

  double get ratio => frames == 0 ? 0.0 : missed / frames;
}

/// Owner 2026-11-22: the frame checks are judged on a PROFILE build
/// (release speed; workflow input `testlab_build: profile`).
///
/// Profile / release build (driver profile runs 45 and 46: the share of
/// missed frames of one screen change moves by 10-20 points from run to
/// run at 40-80 frames, so a 20% limit alone failed a different set each
/// time):
/// * FAIL: the worst frame is over [freezeMs], or more than [failMissed]
///   of at least [failMinFrames] frames are missed.
/// * WARN (in the summary, never fails the run): more than [warnMissed]
///   missed at any frame count; this covers "over [failMissed] with
///   fewer than [failMinFrames] frames".
///
/// Debug build: several times slower, so everything is only indicative:
/// what the first rule called a miss (a frame over [freezeMs], or more
/// than [warnMissed] missed with at least [debugMinFrames] frames) is a
/// WARN, never a FAIL.
///
/// Every other check is strict in every build mode. Pure (no binding, no
/// I/O), so `flutter test` checks it. The same file in the rider and the
/// driver repo; tool/testlab_summary.py reads the [buildLine] and the
/// WARN lines and has the same numbers for its table.
abstract final class SmoothVerdict {
  static const String debug = 'debug';
  static const String profile = 'profile';
  static const String release = 'release';

  /// One frame's budget at 60 Hz.
  static const double budgetMs = 16.667;

  /// A frame longer than this is a visible freeze.
  static const int freezeMs = 200;

  /// FAIL above this share of missed frames, with [failMinFrames].
  static const double failMissed = 0.35;
  static const int failMinFrames = 60;

  /// WARN above this share of missed frames.
  static const double warnMissed = 0.20;

  /// The summary lists a screen change from this share on ("near the limit").
  static const double nearMissed = 0.15;

  /// Debug build only: the share counts from this many frames.
  static const int debugMinFrames = 10;

  /// Said at the start of a debug WARN's detail and in the summary.
  static const String indicative = 'indicative (debug build)';

  /// Said at the start of a profile / release WARN's detail.
  static const String overWarnLimit = 'over the warn limit (not a FAIL)';

  /// The rule in one line, for the check's detail.
  static const String rule =
      'FAIL above 200 ms or > 35% missed with >= 60 frames; '
      'WARN > 20% missed; debug build: WARN only';

  /// The build this code runs in, from the compiler's own constants.
  static String get buildMode => kDebugMode
      ? debug
      : kProfileMode
      ? profile
      : release;

  /// The logcat line (after the MOVERA-TL prefix) that names the build.
  static String buildLine([String? mode]) => 'BUILD mode=${mode ?? buildMode}';

  /// PASS, WARN or FAIL for one screen change's frames in build [mode].
  static SmoothOutcome judge(SmoothStats stats, {String? mode}) {
    final freeze = stats.worstMs > freezeMs;
    if ((mode ?? buildMode) == debug) {
      final many = stats.frames >= debugMinFrames && stats.ratio > warnMissed;
      return freeze || many ? SmoothOutcome.warn : SmoothOutcome.pass;
    }
    if (freeze) return SmoothOutcome.fail;
    if (stats.frames >= failMinFrames && stats.ratio > failMissed) {
      return SmoothOutcome.fail;
    }
    return stats.ratio > warnMissed ? SmoothOutcome.warn : SmoothOutcome.pass;
  }

  /// The check line's detail: a WARN starts with why it is not a FAIL.
  static String detail(SmoothOutcome outcome, String detail, {String? mode}) {
    if (outcome != SmoothOutcome.warn) return detail;
    final why = (mode ?? buildMode) == debug ? indicative : overWarnLimit;
    return '$why: $detail';
  }
}
