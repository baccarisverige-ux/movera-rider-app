import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/shared/widgets/custom_google_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/router/routes.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/presentation/finding_drivers.dart';
import 'package:movera_rider/features/ride_booking/application/ride_restore_coordinator.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Owner, live test 2026-10-26 (N4): "the app suggests adding more money but
/// the rider cannot". Reproduced in Chromium (390 × 844): the raise card
/// appears inside the search sheet at its minimum height; the step buttons
/// sit at the screen's bottom edge and "Set new price", the price field and
/// "Keep waiting" are below it. A swipe on the sheet body did nothing (the
/// body's scroll view swallowed it); only the 22 px handle moved the sheet.
/// No raise-price request was ever sent.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    RideSnapshotStore.epoch = 0;
    FindingDriverController.active = null;
  });

  const rideId = 'n4-raise';

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
          searchStartedAt: DateTime.now().subtract(const Duration(seconds: 50)),
          controller: controller,
        ),
        settings: const RouteSettings(name: AppRoutes.findingDriver),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    for (var i = 0; i < 40 && find.text('Keep waiting').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // Let the sheet settle where the card put it.
    await tester.pump(const Duration(milliseconds: 900));
  }

  testWidgets('the whole raise card, Confirm and Keep waiting included, is on '
      'screen when it appears', (tester) async {
    await openFinding(tester);
    expect(find.text('Want to improve your chances?'), findsOneWidget);
    for (final label in ['+50 kr', 'Set new price', 'Keep waiting']) {
      final rect = tester.getRect(find.text(label));
      expect(
        rect.bottom,
        lessThanOrEqualTo(844),
        reason: '"$label" must be reachable without finding the handle',
      );
    }

    // A step, then the confirm button, both tappable where they are.
    await tester.tap(find.text('+50 kr'));
    await tester.pump(const Duration(milliseconds: 300));
    final confirm = find.textContaining('Confirm');
    expect(confirm, findsOneWidget);
    expect(tester.getRect(confirm).bottom, lessThanOrEqualTo(844));
  });

  // Owner N6: the search map reads the route from above (no tilt with zoom).
  testWidgets('N6: the search map stays flat', (tester) async {
    await openFinding(tester);
    final maps = find.byType(CustomGoogleMap);
    expect(maps, findsWidgets);
    for (final map in tester.widgetList<CustomGoogleMap>(maps)) {
      expect(map.tiltWithZoom, isFalse);
    }
  });

  testWidgets('a drag on the sheet body moves the sheet', (tester) async {
    await openFinding(tester);
    final before = tester.getRect(find.text('Want to improve your chances?'));
    // Pull the sheet down by its text (not the handle), then back up.
    await tester.drag(find.text('Want to improve your chances?'), const Offset(0, 220));
    await tester.pump(const Duration(milliseconds: 600));
    final down = tester.getRect(find.text('Want to improve your chances?'));
    expect(down.top, greaterThan(before.top + 100));
    await tester.drag(find.text('Want to improve your chances?'), const Offset(0, -400));
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.getRect(find.text('Keep waiting')).bottom, lessThanOrEqualTo(844));
  });
}
