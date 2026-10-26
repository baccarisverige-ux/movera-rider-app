import 'package:flutter/material.dart';
import 'package:movera_rider/shared/design_system/motion/movera_curves.dart';
import 'package:movera_rider/shared/design_system/motion/movera_durations.dart';
import 'package:movera_rider/shared/design_system/tokens.dart';
import 'package:smooth_sheets/smooth_sheets.dart';

class MoveraSheetMotion {
  const MoveraSheetMotion({
    required this.forward,
    required this.reverse,
    required this.forwardCurve,
    required this.reverseCurve,
  });

  final Duration forward;
  final Duration reverse;
  final Curve forwardCurve;
  final Curve reverseCurve;

  static MoveraSheetMotion of(BuildContext context) {
    final reduced = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduced) {
      return const MoveraSheetMotion(
        forward: MoveraDurations.reduced,
        reverse: MoveraDurations.reduced,
        forwardCurve: Curves.linear,
        reverseCurve: Curves.linear,
      );
    }
    return const MoveraSheetMotion(
      forward: MoveraDurations.sheetOpen,
      reverse: MoveraDurations.sheetClose,
      forwardCurve: MoveraCurves.open,
      reverseCurve: MoveraCurves.close,
    );
  }

  static const SheetPhysics physics = BouncingSheetPhysics();

  static SheetDecoration decoration({Color color = Colors.white}) {
    return MaterialSheetDecoration(
      size: SheetSize.fit,
      color: color,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(MoveraTokens.radiusSheet),
      ),
    );
  }
}

class MoveraModalSheetRoute<T> extends ModalSheetRoute<T> {
  MoveraModalSheetRoute({
    required super.builder,
    required this.closeDuration,
    super.barrierDismissible,
    super.swipeDismissible,
    super.barrierColor,
    super.barrierLabel,
    super.settings,
    required Duration openDuration,
    required Curve openCurve,
  }) : super(
         transitionDuration: openDuration,
         transitionCurve: openCurve,
         viewportBuilder: (context, child) => SheetViewport(child: child),
       );

  final Duration closeDuration;

  @override
  Duration get reverseTransitionDuration => closeDuration;
}
