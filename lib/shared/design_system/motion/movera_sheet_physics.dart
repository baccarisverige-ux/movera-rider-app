import 'dart:math' as math;

import 'package:smooth_sheets/smooth_sheets.dart';

/// Owner 2026-11-24 (iPhone): a sheet never moves past its top or bottom
/// stop, so nothing slides under the status bar and no band opens under the
/// bottom navigation.
///
/// Like [ClampingSheetPhysics], plus a guard for smooth_sheets 1.2.0: on a
/// drag over scrollable content, `_applyScrollOffset` (scrollable.dart) may
/// ask the physics twice in one move event before it updates the sheet's
/// offset. Both answers were measured from the same old offset, so the
/// sheet overshot its top by the rest of that event and could stay there.
/// Here the second ask is measured from where the first one left the sheet.
class MoveraSheetPhysics extends SheetPhysics with SheetPhysicsMixin {
  MoveraSheetPhysics();

  int? _metricsId;
  double _baseOffset = 0;
  double _applied = 0;

  @override
  double applyPhysicsToOffset(double delta, SheetMetrics metrics) {
    final id = identityHashCode(metrics);
    final double current;
    if (id == _metricsId && metrics.offset == _baseOffset) {
      // Same event, offset not yet updated: continue from the first answer.
      current = _baseOffset + _applied;
    } else {
      _metricsId = id;
      _baseOffset = metrics.offset;
      _applied = 0;
      current = metrics.offset;
    }
    final double result;
    if (delta > 0) {
      result = math.max(
        0.0,
        math.min(metrics.maxOffset, current + delta) - current,
      );
    } else if (delta < 0) {
      result = math.min(
        0.0,
        math.max(metrics.minOffset, current + delta) - current,
      );
    } else {
      result = 0;
    }
    _applied += result;
    return result;
  }
}
