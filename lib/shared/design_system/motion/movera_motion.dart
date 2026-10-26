import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:movera_rider/shared/design_system/motion/movera_curves.dart';
import 'package:movera_rider/shared/design_system/motion/movera_durations.dart';

export 'movera_curves.dart';
export 'movera_durations.dart';
export 'movera_sheet_motion.dart';

abstract final class MoveraMotion {
  static bool reduced(BuildContext context) {
    return MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  }

  static Duration of(BuildContext context, Duration normal) {
    return reduced(context) ? MoveraDurations.reduced : normal;
  }

  static Widget selection({required bool selected, required Widget child}) {
    return AnimatedScale(
      scale: selected ? 1.03 : 1,
      duration: MoveraDurations.micro,
      curve: MoveraCurves.micro,
      child: child,
    );
  }

  static Widget appear(BuildContext context, Widget child) {
    if (reduced(context)) return child;
    return child
        .animate()
        .fadeIn(duration: MoveraDurations.normal, curve: MoveraCurves.open)
        .slideY(
          begin: 0.04,
          end: 0,
          duration: MoveraDurations.normal,
          curve: MoveraCurves.open,
        );
  }
}
