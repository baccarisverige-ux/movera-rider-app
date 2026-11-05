import 'dart:async';

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
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/active_ride/application/active_ride_controller.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/presentation/finding_drivers.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/shared/widgets/custom_google_map.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A feed that never sends anything, so only the screen itself could change
/// the ride status.
class _QuietRealtime implements RideRealtime {
  final StreamController<RideRealtimeEvent> _controller =
      StreamController<RideRealtimeEvent>.broadcast(sync: true);

  @override
  bool get supportsRiderSignals => false;
  @override
  Stream<RideRealtimeEvent> subscribe(String rideId) => _controller.stream;
  @override
  Future<void> reconnectAndResync(String rideId) async {}
  @override
  Future<void> sendSignal({
    required String rideId,
    required RideRealtimeSignal signal,
    String? message,
  }) async {}
  @override
  void unsubscribe() {}
  @override
  void cancelRide() {}
  @override
  void researchAfterDriverCancel() {}
  @override
  void dispose() => _controller.close();
}

/// B16 (2026-11-04): behaviour tests for the Finding and Waiting screens
/// that replace source-reading guards (archived in
/// Rules/archive/old-tests/movera-rider-app/).
void main() {
  late InProcessMockClient server;
  ApiClient api() => ApiClient(client: server);

  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    server = InProcessMockClient();
    RideSnapshotStore.epoch = 0;
    FindingDriverController.active = null;
    AppScope.instance.ride
      ..rideId = null
      ..suppressRestore = false
      ..restoreFromBackend(RideStatus.idle);
  });

  Future<void> seed(String id, RideStatus status, String serverStatus) async {
    server.rides[id] = {'id': id, 'status': serverStatus};
    AppScope.instance.ride.restoreFromBackend(status, id: id);
  }

  Set<String> markerIds(WidgetTester tester) => {
    for (final map in tester.widgetList<CustomGoogleMap>(
      find.byType(CustomGoogleMap, skipOffstage: false),
    ))
      for (final m in map.markers ?? const <Marker>{}) m.markerId.value,
  };

  Future<GlobalKey<NavigatorState>> pumpHost(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => MaterialApp(
          navigatorKey: nav,
          home: const Scaffold(body: Text('journey-home')),
        ),
      ),
    );
    return nav;
  }

  Future<void> pumpFinding(WidgetTester tester) async {
    const rideId = 'b16-finding';
    await seed(rideId, RideStatus.findingDriver, 'searching');
    // No driver accepts during the test: only the server may assign one.
    final realtime = MockRideRealtime(assignAfter: const Duration(days: 1));
    addTearDown(realtime.dispose);
    final nav = await pumpHost(tester);
    nav.currentState!.push(
      RideStageTransition(
        FindingDrivers(
          pickupAddress: 'Sveavägen 1',
          destinationAddress: 'Hornsgatan 2',
          pickupPosition: const LatLng(59.34, 18.05),
          destinationPosition: const LatLng(59.31, 18.04),
          rideType: 'Movera',
          price: 259,
          paymentMethod: 'Apple Pay',
          realtime: realtime,
          controller: FindingDriverController(realtime: realtime, api: api()),
        ),
        settings: const RouteSettings(name: AppRoutes.findingDriver),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(FindingDrivers), findsOneWidget);
  }

  testWidgets('Finding: no widget timer assigns a driver; only the server '
      'can', (tester) async {
    await pumpFinding(tester);
    // The old screen invented a driver after 12 s.
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.byType(FindingDrivers), findsOneWidget);
    expect(find.byType(WaitingForDriver), findsNothing);
    expect(AppScope.instance.ride.status, RideStatus.findingDriver);
    expect(markerIds(tester), isNot(contains('car-a')));
    expect(find.textContaining('Confirming your ride'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('Finding: cancelling uses the cancel sheet, never the old '
      '"Confirming your ride" dialog', (tester) async {
    await pumpFinding(tester);
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.widgetWithText(TextButton, 'Cancel request'), findsOneWidget);
    expect(find.textContaining('Confirming your ride'), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });

  Future<void> pumpWaiting(WidgetTester tester) async {
    const rideId = 'b16-waiting';
    await seed(rideId, RideStatus.driverAssigned, 'accepted');
    final realtime = _QuietRealtime();
    final nav = await pumpHost(tester);
    nav.currentState!.push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: AppRoutes.waitingForDriver),
        builder: (_) => WaitingForDriver(
          pickupAddress: 'Sveavägen 1',
          destinationAddress: 'Hornsgatan 2',
          pickupPosition: const LatLng(59.34, 18.05),
          destinationPosition: const LatLng(59.31, 18.04),
          rideType: 'Movera',
          price: 259,
          paymentMethod: 'Apple Pay',
          rideId: rideId,
          realtime: realtime,
          controller: ActiveRideController(api: api()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(WaitingForDriver), findsOneWidget);
  }

  testWidgets('Waiting: opening the screen does not mark the driver as '
      'arriving', (tester) async {
    await pumpWaiting(tester);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(AppScope.instance.ride.status, RideStatus.driverAssigned);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('Waiting: shows no invented driver, plate or ETA', (
    tester,
  ) async {
    await pumpWaiting(tester);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    for (final fake in [
      'L - 2323 F',
      'Merle Feeney',
      '5 mins',
      'Confirming your ride',
    ]) {
      expect(
        find.textContaining(fake, findRichText: true),
        findsNothing,
        reason: fake,
      );
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('Waiting: cancelling uses the cancel sheet, never the old '
      '"Confirming your ride" dialog', (tester) async {
    await pumpWaiting(tester);
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Cancel request'), findsOneWidget);
    expect(find.textContaining('Confirming your ride'), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
