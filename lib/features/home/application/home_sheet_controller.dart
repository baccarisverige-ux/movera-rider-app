import 'dart:async';

import 'package:flutter/material.dart';
import 'package:movera_rider/shared/design_system/motion/movera_motion.dart';
import 'package:smooth_sheets/smooth_sheets.dart';

/// Owns Home sheet motion and its idle-collapse timer.
///
/// Presentation state remains in Home; this controller only centralizes the
/// sheet mechanics so route/address/map behavior is not coupled to them.
class HomeSheetController {
  HomeSheetController({
    required SheetController controller,
    required double Function() minPixels,
    required double Function() midPixels,
  }) : _controller = controller,
       _minPixels = minPixels,
       _midPixels = midPixels;

  final SheetController _controller;
  final double Function() _minPixels;
  final double Function() _midPixels;
  Timer? _idleTimer;

  bool get isAtMiddle {
    if (!_controller.hasClient) return false;
    final offset = _controller.metrics?.offset;
    if (offset == null) return false;
    return (offset - _midPixels()).abs() <= 1.5;
  }

  void cancelIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = null;
  }

  void scheduleIdleClose({
    required bool accessibleNavigation,
    required bool Function() isMounted,
  }) {
    // Restart, never toggle: the sheet listener calls this on every metrics
    // tick at the middle stop, so an armed timer must survive a repeat call.
    cancelIdleTimer();
    if (accessibleNavigation || !isAtMiddle) return;
    _idleTimer = Timer(const Duration(seconds: 3), () {
      _idleTimer = null;
      if (!isMounted() || !isAtMiddle) return;
      unawaited(
        animateTo(
          SheetOffset.absolute(_minPixels()),
          duration: MoveraDurations.large,
          curve: MoveraCurves.close,
        ),
      );
    });
  }

  Future<void> animateTo(
    SheetOffset target, {
    Duration duration = MoveraDurations.large,
    Curve curve = MoveraCurves.open,
  }) async {
    if (!_controller.hasClient) return;
    await _controller.animateTo(target, duration: duration, curve: curve);
  }

  Future<void> open() => animateTo(const SheetOffset(1));

  void close() {
    unawaited(animateTo(SheetOffset.absolute(_minPixels())));
  }

  void toggle({required double expandedThreshold}) {
    final min = _minPixels();
    final mid = _midPixels();
    final offset = _controller.hasClient
        ? (_controller.metrics?.offset ?? min)
        : min;
    final midpoint = (min + mid) / 2;
    final SheetOffset target;
    if (offset > mid + expandedThreshold) {
      target = SheetOffset.absolute(mid);
    } else if (offset > midpoint) {
      target = SheetOffset.absolute(min);
    } else {
      target = SheetOffset.absolute(mid);
    }
    unawaited(animateTo(target, duration: MoveraDurations.large));
  }

  void dispose() => cancelIdleTimer();
}
