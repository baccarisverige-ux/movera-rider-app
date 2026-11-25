import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/app/movera_scroll_behavior.dart';
import 'package:movera_rider/shared/design_system/motion/movera_sheet_motion.dart';
import 'package:smooth_sheets/smooth_sheets.dart';

/// Owner 2026-11-24: nothing in the rider app may bounce past its edge on
/// iOS. Behaviour checks (no source reading): the app's scroll behaviour
/// hands every scroll view clamping physics on iOS, and the shared sheet
/// physics is not a bouncing one.
void main() {
  testWidgets('Movera scroll behaviour gives clamping physics on iOS', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    late ScrollPhysics physics;
    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const MoveraScrollBehavior(),
        home: Builder(
          builder: (context) {
            physics = ScrollConfiguration.of(context).getScrollPhysics(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(physics, isA<ClampingScrollPhysics>());
    expect(physics, isNot(isA<BouncingScrollPhysics>()));
    debugDefaultTargetPlatformOverride = null;
  });

  test('the shared Movera sheet physics never bounces', () {
    expect(MoveraSheetMotion.physics, isNot(isA<BouncingSheetPhysics>()));
  });
}
