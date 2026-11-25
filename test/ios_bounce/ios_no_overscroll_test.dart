import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/app/movera_scroll_behavior.dart';
import 'package:movera_rider/shared/design_system/motion/movera_sheet_motion.dart';
import 'package:movera_rider/shared/design_system/motion/movera_sheet_physics.dart';
import 'package:smooth_sheets/smooth_sheets.dart';

/// Owner 2026-11-24 (iPhone, TestFlight): sliding the Home sheet up moved it
/// past its top - "Where to?" went under the status bar and an empty band
/// opened under the bottom navigation. Cause: BouncingSheetPhysics lets a
/// sheet be over-dragged up to 120 px beyond its top, and iOS scroll views
/// bounce by default. Every rider sheet and scroll view must stop at its
/// edge on iOS.
void main() {
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets('a Movera sheet dragged past its top never goes above it '
      '(iOS)', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final controller = SheetController();
    const screenH = 800.0;
    const navH = 60.0;
    await tester.binding.setSurfaceSize(const Size(400, screenH));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const MoveraScrollBehavior(),
        home: Scaffold(
          body: Stack(
            children: [
              SheetViewport(
                child: Sheet(
                  controller: controller,
                  initialOffset: const SheetOffset.absolute(200),
                  physics: MoveraSheetMotion.physics,
                  snapGrid: const SheetSnapGrid(
                    snaps: [SheetOffset.absolute(200), SheetOffset(1)],
                  ),
                  scrollConfiguration: const SheetScrollConfiguration(),
                  child: SizedBox(
                    key: const Key('sheet'),
                    height: 600,
                    child: SingleChildScrollView(
                      primary: true,
                      child: Column(
                        children: [
                          const SizedBox(height: 300, child: Text('Where to?')),
                          const SizedBox(height: 240),
                          Container(
                            key: const Key('nav'),
                            height: navH,
                            color: Colors.blue,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final max = controller.metrics!.maxOffset;

    // A long slow drag up, far beyond the top stop.
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Where to?')),
    );
    // MoveraSheetPhysics also covers smooth_sheets 1.2.0 asking the physics
    // twice per move event with a stale offset (which let even
    // ClampingSheetPhysics overshoot here by 1.2 px and stay there).
    double? peak;
    for (var i = 0; i < 40; i++) {
      await gesture.moveBy(const Offset(0, -20));
      await tester.pump(const Duration(milliseconds: 16));
      final off = controller.metrics!.offset;
      expect(
        off,
        lessThanOrEqualTo(max + 0.01),
        reason: 'sheet over-dragged past its top during the drag',
      );
      if (off > max) {
        expect(
          off,
          lessThanOrEqualTo((peak ?? off) + 0.01),
          reason: 'sheet keeps climbing past its top',
        );
        peak = off;
      }
    }
    await gesture.up();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    expect(controller.metrics!.offset, closeTo(max, 0.5));
    // Sheet bottom (and the nav at its bottom) back at the screen bottom.
    expect(
      tester.getBottomLeft(find.byKey(const Key('nav'))).dy,
      closeTo(screenH, 0.5),
    );

    expect(
      tester.getTopLeft(find.byKey(const Key('sheet'))).dy,
      greaterThanOrEqualTo(screenH - max - 0.5),
    );
    debugDefaultTargetPlatformOverride = null;
  });

  test('the shared sheet physics is clamping, not bouncing', () {
    expect(MoveraSheetMotion.physics, isA<MoveraSheetPhysics>());
  });

  testWidgets('app scroll views clamp on iOS (no bounce gap)', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final controller = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const MoveraScrollBehavior(),
        home: ListView(
          controller: controller,
          children: List.generate(
            40,
            (i) => SizedBox(height: 50, child: Text('row $i')),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('row 2')),
    );
    await gesture.moveBy(const Offset(0, 300));
    await tester.pump();
    expect(controller.offset, 0, reason: 'list pulled down past its top');
    await gesture.up();
    await tester.pumpAndSettle();
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();
    final g2 = await tester.startGesture(tester.getCenter(find.text('row 39')));
    await g2.moveBy(const Offset(0, -300));
    await tester.pump();
    expect(
      controller.offset,
      controller.position.maxScrollExtent,
      reason: 'list pushed up past its end',
    );
    await g2.up();
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;
  });
}
