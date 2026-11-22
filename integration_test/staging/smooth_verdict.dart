import 'package:flutter/foundation.dart' show kDebugMode, kProfileMode;

/// How a frame check (`TRANSITION:<name>:SMOOTH`) ends.
enum SmoothOutcome { pass, warn, fail }

/// Owner 2026-11-22: the frame checks are judged on a PROFILE build
/// (release speed; workflow input `testlab_build: profile`). A debug build
/// is several times slower, so there a slow frame is only indicative: it
/// is written as a WARN line, shown in the summary, and never fails the
/// run. Every other check is strict in every build mode.
///
/// Pure (no binding, no I/O), so `flutter test` checks it. The same file
/// in the rider and the driver repo; tool/testlab_summary.py reads the
/// [buildLine] and the WARN lines.
abstract final class SmoothVerdict {
  static const String debug = 'debug';
  static const String profile = 'profile';
  static const String release = 'release';

  /// Said at the start of a WARN's detail and in the summary.
  static const String indicative = 'indicative (debug build)';

  /// The build this code runs in, from the compiler's own constants.
  static String get buildMode => kDebugMode
      ? debug
      : kProfileMode
      ? profile
      : release;

  /// The logcat line (after the MOVERA-TL prefix) that names the build.
  static String buildLine([String? mode]) => 'BUILD mode=${mode ?? buildMode}';

  /// Not smooth is a FAIL, except on a debug build: a WARN.
  static SmoothOutcome judge({required bool smooth, String? mode}) {
    if (smooth) return SmoothOutcome.pass;
    return (mode ?? buildMode) == debug
        ? SmoothOutcome.warn
        : SmoothOutcome.fail;
  }

  /// The check line's detail: a WARN starts with [indicative].
  static String detail(SmoothOutcome outcome, String detail) =>
      outcome == SmoothOutcome.warn ? '$indicative: $detail' : detail;
}
