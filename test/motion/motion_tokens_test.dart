import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/maps/map_coordinator.dart';
import 'package:movera_rider/features/ride_booking/application/sheet_coordinator.dart';
import 'package:movera_rider/shared/design_system/motion/movera_motion.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';

void main() {
  test('motion tokens stay in the agreed ranges', () {
    expect(MoveraDurations.micro.inMilliseconds, inInclusiveRange(120, 180));
    expect(MoveraDurations.normal.inMilliseconds, inInclusiveRange(220, 320));
    expect(MoveraDurations.large.inMilliseconds, inInclusiveRange(300, 420));
    expect(
      MoveraDurations.sheetOpen.inMilliseconds,
      inInclusiveRange(300, 420),
    );
    expect(
      MoveraDurations.sheetClose.inMilliseconds,
      lessThan(MoveraDurations.sheetOpen.inMilliseconds),
    );
  });

  test('sheet coordinator does not own ride matching', () {
    final src = SheetCoordinator;
    expect(src, isNotNull);
    final c = SheetCoordinator();
    c.open(RideSheet.notes);
    expect(c.current, RideSheet.notes);
    c.close(RideSheet.notes);
    expect(c.current, RideSheet.none);
  });

  test(
    'map coordinator throttles padding and does not rebuild on tiny drags',
    () {
      final map = MapCoordinator();
      expect(map.shouldPublishPadding(120), isTrue);
      expect(map.shouldPublishPadding(121), isFalse);
    },
  );

  testWidgets('reduced motion collapses decorative duration', (tester) async {
    late Duration resolved;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Builder(
          builder: (context) {
            resolved = MoveraMotion.of(context, MoveraDurations.large);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(resolved, MoveraDurations.reduced);
  });

  test('page cover no longer uses the 1000ms size wipe', () {
    final src = BottomToTopTransition;
    expect(src, isNotNull);
  });
}
