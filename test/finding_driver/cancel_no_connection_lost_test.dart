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
import 'package:movera_rider/features/ride_booking/application/ride_restore_coordinator.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The server transport lets go of the trip on a committed cancel and
/// marks the shared connection disconnected (ApiRideRealtime.cancelRide,
/// lib/core/realtime/api_ride_realtime.dart: connection.markDisconnected()).
class _ReleasingRealtime extends MockRideRealtime {
  _ReleasingRealtime({super.api}) : super(assignAfter: const Duration(days: 1));

  @override
  void cancelRide() {
    super.cancelRide();
    AppScope.instance.realtime.markDisconnected();
  }
}

/// proof5 (2026-11-07, item 5): Finding showed "Connection lost" while the
/// rider cancelled. The cancel commits (and the transport marks the
/// connection disconnected) while the cancel sheet is still up; the screen
/// hid the banner only from _finishCommittedCancel on (code order).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('a committed cancel never shows Connection lost on Finding', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    RideSnapshotStore.epoch = 0;
    FindingDriverController.active = null;
    RideRestoreCoordinator.instance.showing = RestoredSurface.home;
    final server = InProcessMockClient();
    final api = ApiClient(client: server);
    final realtime = _ReleasingRealtime(api: api);
    addTearDown(realtime.dispose);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const rideId = 'cnl-1';
    server.rides[rideId] = {'id': rideId, 'status': 'findingDriver'};
    AppScope.instance.ride
      ..rideId = rideId
      ..status = RideStatus.findingDriver
      ..suppressRestore = false
      ..authoritativeVersion = null
      ..authoritativeUpdatedAt = null;
    AppScope.instance.realtime.markConnected();
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(375, 812),
        minTextAdapt: true,
        splitScreenMode: true,
        builder: (_, __) => MaterialApp(
          navigatorKey: nav,
          home: const Scaffold(body: Text('cnl-home')),
        ),
      ),
    );
    nav.currentState!.push(
      RideStageTransition(
        FindingDrivers(
          pickupAddress: 'Stockholm Central',
          destinationAddress: 'Arlanda Airport',
          pickupPosition: const LatLng(59.3300, 18.0590),
          destinationPosition: const LatLng(59.6519, 17.9186),
          rideType: 'Movera',
          price: 349,
          paymentMethod: 'Apple Pay',
          realtime: realtime,
          controller: FindingDriverController(realtime: realtime, api: api),
        ),
        settings: const RouteSettings(name: AppRoutes.findingDriver),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(FindingDrivers), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.widgetWithText(TextButton, 'Cancel request'));
    await tester.pump();

    var lostSeen = false;
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      if (find.text('Connection lost').evaluate().isNotEmpty) lostSeen = true;
      if (find.text('Why are you cancelling?').evaluate().isNotEmpty) break;
    }
    expect(find.text('Why are you cancelling?'), findsOneWidget);
    expect(AppScope.instance.ride.status, RideStatus.cancelledByRider);
    expect(
      lostSeen,
      isFalse,
      reason: '"Connection lost" shown while cancelling',
    );
  });
}
