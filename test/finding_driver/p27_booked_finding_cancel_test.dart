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
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/presentation/finding_drivers.dart';
import 'package:movera_rider/features/ride_booking/application/ride_restore_coordinator.dart';
import 'package:movera_rider/features/ride_booking/data/ride_projection.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Contract v0.18.152 (`bookedRideSeen.searchSeen.riderApp`; owner
/// 2026-11-21 15:00 (A)): a booked ride whose search started and that no
/// list driver ever held opens the normal Finding driver screen. There the
/// cancel follows the BOOKED rules: the server's cancel preview line
/// ("Cancelling now costs …" under 1 h before the pickup), never "free", and
/// a booked ride never shows "No driver nearby".
class _Realtime extends RideRealtime {
  final c = StreamController<RideRealtimeEvent>.broadcast();
  @override
  Stream<RideRealtimeEvent> subscribe(String rideId) => c.stream;
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
  void dispose() => c.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  late InProcessMockClient server;
  late ApiClient api;
  late _Realtime realtime;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RideSnapshotStore.epoch = 0;
    FindingDriverController.active = null;
    server = InProcessMockClient();
    api = ApiClient(client: server);
    realtime = _Realtime();
    RideRestoreCoordinator.instance.showing = RestoredSurface.home;
  });

  tearDown(() {
    FindingDrivers.cancelFeeClock = DateTime.now;
    realtime.dispose();
  });

  Future<void> openFinding(WidgetTester tester, String rideId) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    server.rides[rideId] = {'id': rideId, 'status': 'findingDriver'};
    AppScope.instance.ride
      ..rideId = rideId
      ..status = RideStatus.findingDriver
      ..suppressRestore = false
      ..authoritativeVersion = null
      ..authoritativeUpdatedAt = null;
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(375, 812),
        minTextAdapt: true,
        splitScreenMode: true,
        builder: (_, __) => MaterialApp(
          navigatorKey: nav,
          home: const Scaffold(body: Center(child: Text('p27-home'))),
        ),
      ),
    );
    nav.currentState!.push(
      RideStageTransition(
        FindingDrivers(
          pickupAddress: 'Sergels torg',
          destinationAddress: 'Medborgarplatsen',
          pickupPosition: const LatLng(59.3326, 18.0649),
          destinationPosition: const LatLng(59.3143, 18.0735),
          rideType: 'Movera',
          price: 242,
          paymentMethod: 'Cash',
          realtime: realtime,
          controller: FindingDriverController(realtime: realtime, api: api),
        ),
        settings: const RouteSettings(name: AppRoutes.findingDriver),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(FindingDrivers), findsOneWidget);
  }

  /// The trip's projection on its stream: searching; a booked ride carries
  /// its pickup time and the server's cancel preview.
  Future<void> project(
    WidgetTester tester,
    String rideId, {
    required bool booked,
    Map<String, Object?>? searchStep,
  }) async {
    final pickupAt = DateTime.now().toUtc().add(const Duration(minutes: 25));
    realtime.c.add(
      RideRealtimeEvent(
        tripId: rideId,
        status: RideStatus.findingDriver,
        sequence: 0,
        payload: {
          wholeProjectionKey: true,
          if (booked) bookedPickupAtKey: pickupAt.toIso8601String(),
          if (booked)
            cancelPreviewKey: {
              'feeNow': {'amountMinor': 5000, 'currency': 'SEK'},
              'kind': 'cancel',
            },
          if (searchStep != null) searchStepKey: searchStep,
        },
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> openCancel(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Cancel ride?'), findsOneWidget);
  }

  testWidgets('booked ride being searched: the cancel sheet shows the booking '
      'fee from the server preview, never free', (tester) async {
    const rideId = 'p27-booked';
    await openFinding(tester, rideId);
    await project(tester, rideId, booked: true);
    await openCancel(tester);
    final note = find.byKey(const ValueKey('cancel-fee-note'));
    expect(note, findsOneWidget);
    final text = tester.widget<Text>(note).data!;
    expect(text, startsWith('Cancelling now costs '));
    expect(text, contains('50'));
    expect(find.text('No fee to cancel this ride.'), findsNothing);
  });

  testWidgets('live ride being searched: no fee line (unchanged)', (
    tester,
  ) async {
    const rideId = 'p27-live';
    await openFinding(tester, rideId);
    await project(tester, rideId, booked: false);
    await openCancel(tester);
    expect(find.byKey(const ValueKey('cancel-fee-note')), findsNothing);
  });

  testWidgets('a booked ride never shows "No driver nearby"; a live ride '
      'still does', (tester) async {
    const step = {
      'id': 'no_driver_nearby',
      'kind': 'no_driver_nearby',
      'message': 'No driver nearby',
    };
    await openFinding(tester, 'p27-booked-step');
    await project(tester, 'p27-booked-step', booked: true, searchStep: step);
    final controller = FindingDriverController.active!;
    expect(controller.booked, isTrue);
    expect(controller.searchStep, isNull);
    expect(
      find.text('No driver nearby right now. We keep searching for you.'),
      findsNothing,
    );
  });

  testWidgets('a live ride keeps its "No driver nearby" step', (tester) async {
    const step = {
      'id': 'no_driver_nearby',
      'kind': 'no_driver_nearby',
      'message': 'No driver nearby',
    };
    await openFinding(tester, 'p27-live-step');
    await project(tester, 'p27-live-step', booked: false, searchStep: step);
    final controller = FindingDriverController.active!;
    expect(controller.booked, isFalse);
    expect(controller.searchStep?.kind, 'no_driver_nearby');
  });

  test('restore: GET /rider/trips/active with a booked trip in searching '
      'opens Finding driver, in accepted the driver screen', () {
    Map<String, dynamic> booked(String status) => {
      'tripId': 'trp_bkd',
      'kind': 'scheduled',
      'status': status,
      'version': 4,
      'categoryId': 'economy',
      'scheduledAt': DateTime.now()
          .toUtc()
          .add(const Duration(minutes: 25))
          .toIso8601String(),
      'pickup': {'address': 'Sergels torg', 'lat': 59.3326, 'lng': 18.0649},
      'dropoff': {
        'address': 'Medborgarplatsen',
        'lat': 59.3143,
        'lng': 18.0735,
      },
      'fare': {'amountMinor': 24200, 'currency': 'SEK'},
      'paymentMethod': 'cash',
      if (status == 'accepted')
        'driver': {'driverId': 'drv_1', 'firstName': 'Ali'},
    };
    final coordinator = RideRestoreCoordinator(reader: () async => null);
    for (final status in ['searching', 'offered']) {
      final snapshot = RideProjection.toSnapshot(booked(status));
      expect(coordinator.surfaceFor(snapshot), RestoredSurface.finding);
    }
    final accepted = RideProjection.toSnapshot(booked('accepted'));
    expect(coordinator.surfaceFor(accepted), RestoredSurface.waiting);
    expect(accepted!.driver?.firstName, 'Ali');
  });
}
