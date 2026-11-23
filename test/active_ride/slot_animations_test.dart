import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/active_ride/presentation/ride_slot_animations.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/driver_profile/presentation/driver_on_way_card.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/matched_driver.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/shared/widgets/slot_motion.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Owner 2026-11-23: the approved panel animations (same style and 240x96
/// slot as the search radar) at the top of the panel; "reduce motion" keeps
/// them still. Driver on the way: APPROVED-driver-coming.html.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    SlotMotion.enabled = true;
    addTearDown(() => SlotMotion.enabled = false);
  });

  Future<MockRideRealtime> pumpWaiting(
    WidgetTester tester,
    RideStatus status,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const rideId = 'ride_slot_anim';
    RideSnapshotStore.epoch = 0;
    AppScope.instance.ride
      ..rideId = null
      ..suppressRestore = false
      ..restoreFromBackend(status, id: rideId);
    final realtime = MockRideRealtime(assignAfter: const Duration(days: 1))
      ..primeResume(status: status, driver: _driver);
    await tester.pumpWidget(
      MaterialApp(
        home: WaitingForDriver(
          pickupAddress: 'Sveavägen 1',
          destinationAddress: 'Centralstation',
          pickupPosition: const LatLng(59.34, 18.05),
          destinationPosition: const LatLng(59.33, 18.06),
          rideType: 'Movera',
          price: 190,
          paymentMethod: 'cash',
          rideId: rideId,
          driver: _driver,
          realtime: realtime,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return realtime;
  }

  Future<void> done(WidgetTester tester, MockRideRealtime realtime) async {
    realtime.dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  Widget host(Widget child, {required bool still}) => MediaQuery(
    data: MediaQueryData(disableAnimations: still),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: child),
    ),
  );

  testWidgets('driver on the way: the animation is at the top of the panel, '
      'above the driver card', (tester) async {
    final realtime = await pumpWaiting(tester, RideStatus.driverAssigned);
    final anim = find.byType(DriverComingAnimation);
    expect(anim, findsOneWidget);
    expect(tester.getSize(anim).height, SlotScene.height);
    expect(
      tester.getRect(anim).bottom,
      lessThanOrEqualTo(tester.getRect(find.byType(DriverOnWayCard)).top),
    );
    await done(tester, realtime);
  });

  testWidgets('driver on the way: moves, and stands still with reduce motion', (
    tester,
  ) async {
    await tester.pumpWidget(host(const DriverComingAnimation(), still: false));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpWidget(host(const DriverComingAnimation(), still: true));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  // On trip: on-trip-animation.html (approved, LAUNCH-RULE.md).
  testWidgets('on trip: the animation is at the top of the trip panel', (
    tester,
  ) async {
    final realtime = await pumpWaiting(tester, RideStatus.tripInProgress);
    final anim = find.byType(OnTripAnimation);
    expect(anim, findsOneWidget);
    expect(find.byType(DriverComingAnimation), findsNothing);
    expect(tester.getSize(anim).height, SlotScene.height);
    expect(
      tester.getRect(anim).bottom,
      lessThanOrEqualTo(tester.getRect(find.byType(DriverOnWayCard)).top),
    );
    await done(tester, realtime);
  });

  testWidgets('on trip: moves, and stands still with reduce motion', (
    tester,
  ) async {
    await tester.pumpWidget(host(const OnTripAnimation(), still: false));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpWidget(host(const OnTripAnimation(), still: true));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}

const _driver = MatchedDriver(
  id: 'driver_slot',
  firstName: 'Alex',
  vehicleMake: 'Volvo',
  vehicleModel: 'EX30',
  plate: 'ABC 123',
);
