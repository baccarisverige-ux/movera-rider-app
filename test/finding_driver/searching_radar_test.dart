import 'package:movera_rider/shared/widgets/slot_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/router/routes.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/presentation/finding_drivers.dart';
import 'package:movera_rider/features/finding_driver/presentation/searching_radar.dart';
import 'package:movera_rider/core/constants/appassets.dart';
import 'package:movera_rider/features/ride_booking/application/ride_restore_coordinator.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Owner 2026-11-23: "We also change this car card" (approved
/// APPROVED-searching-radar.html): the radar replaces the car picture at the
/// same height; reduce motion keeps it still.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    SlotMotion.enabled = true;
    addTearDown(() => SlotMotion.enabled = false);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    RideSnapshotStore.epoch = 0;
    FindingDriverController.active = null;
  });

  const rideId = 'radar-1';

  Future<void> openFinding(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    RideRestoreCoordinator.instance.showing = RestoredSurface.home;
    final server = InProcessMockClient();
    final api = ApiClient(client: server);
    final realtime = MockRideRealtime(
      assignAfter: const Duration(days: 1),
      api: api,
    );
    addTearDown(realtime.dispose);
    server.rides[rideId] = {
      'id': rideId,
      'status': 'findingDriver',
      'version': 1,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      'categoryId': 'economy',
      'paymentMethodId': 'cash',
    };
    AppScope.instance.ride
      ..rideId = rideId
      ..status = RideStatus.findingDriver
      ..suppressRestore = false
      ..authoritativeVersion = 1
      ..bookedCategoryId = 'economy'
      ..bookedPaymentMethodId = 'cash';
    final controller = FindingDriverController(realtime: realtime, api: api);
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(375, 812),
        minTextAdapt: true,
        splitScreenMode: true,
        builder: (_, __) => MaterialApp(
          navigatorKey: nav,
          home: const Scaffold(body: Center(child: Text('n4-home'))),
        ),
      ),
    );
    nav.currentState!.push(
      RideStageTransition(
        FindingDrivers(
          pickupAddress: 'Klockarvägen 37, Södertälje',
          destinationAddress: 'Stockholm Central Station, Centralplan 15',
          pickupPosition: const LatLng(59.1962, 17.6279),
          destinationPosition: const LatLng(59.33, 18.0587),
          rideType: 'Movera',
          price: 824,
          paymentMethod: 'Cash',
          realtime: realtime,
          // The raise card shows after 45 s of searching (and the search
          // has not reached the 3-minute "still looking" mark).
          searchStartedAt: DateTime.now(),
          controller: controller,
        ),
        settings: const RouteSettings(name: AppRoutes.findingDriver),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // Let the sheet settle where the card put it.
    await tester.pump(const Duration(milliseconds: 900));
  }

  testWidgets('the radar sits where the car picture was', (tester) async {
    await openFinding(tester);
    expect(find.byType(SearchingRadar), findsOneWidget);
    final pics = find.byWidgetPredicate(
      (w) =>
          w is Image &&
          w.image is AssetImage &&
          (w.image as AssetImage).assetName == AppAssets.scheduleRideCar,
    );
    expect(pics, findsNothing);
    expect(
      tester.getSize(find.byType(SearchingRadar)).height,
      SlotScene.height,
    );
    expect(find.text('Finding your driver'), findsWidgets);
  });

  Widget host({required bool still}) => MediaQuery(
    data: MediaQueryData(disableAnimations: still),
    child: const Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: SearchingRadar()),
    ),
  );

  testWidgets('the radar turns', (tester) async {
    await tester.pumpWidget(host(still: false));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.binding.hasScheduledFrame, isTrue);
  });

  testWidgets('reduce motion: the radar stands still', (tester) async {
    await tester.pumpWidget(host(still: true));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(find.byType(SearchingRadar), findsOneWidget);
  });
}
