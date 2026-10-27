import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/navigator_key.dart';
import 'package:movera_rider/app/router/ride_navigator.dart';
import 'package:movera_rider/features/ride_booking/application/ride_restore_coordinator.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';

/// Audit Phase 5, P5-R1: after a reload, a ride screen is the root of the
/// navigator (the restore gate's child). When that ride ends ("Cancelled by
/// Movera") and the rider taps "Back to home", RideNavigator.home has nothing
/// to pop and leaves Home for the next frame. On the web nothing asked for
/// that frame, so the rider stayed on the dead ride screen until something
/// else repainted (live build, measured in Chromium: 25 s and counting).
void main() {
  testWidgets('Back to home from a restored ride reaches Home without '
      'waiting for an unrelated repaint', (tester) async {
    final coordinator = RideRestoreCoordinator.instance;
    final previousHook = coordinator.onReplaceRoot;
    final previousShowing = coordinator.showing;
    addTearDown(() {
      coordinator.onReplaceRoot = previousHook;
      coordinator.showing = previousShowing;
    });
    AppScope.instance.ride.restoreFromBackend(
      RideStatus.cancelledByAdmin,
      id: 'p5-restored',
    );

    Widget? replacedWith;
    coordinator.onReplaceRoot = (page) => replacedWith = page;
    coordinator.showing = RestoredSurface.waiting;

    late BuildContext rideContext;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: moveraNavigatorKey,
        home: Builder(
          builder: (context) {
            rideContext = context;
            return const Scaffold(body: Text('restored-ride'));
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(moveraNavigatorKey.currentState!.canPop(), isFalse);
    expect(tester.binding.hasScheduledFrame, isFalse);

    RideNavigator.home(rideContext, status: RideStatus.cancelledByAdmin);

    // The hand-over to Home must ask for the frame it waits for.
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pump();
    expect(replacedWith, isNotNull);
    expect(coordinator.showing, RestoredSurface.home);
  });
}
