import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/router/routes.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/data/pending_cancel_store.dart';
import 'package:movera_rider/features/finding_driver/presentation/finding_drivers.dart';
import 'package:movera_rider/features/history/data/on_demand_ride_history_store.dart';
import 'package:movera_rider/features/ride_booking/application/ride_restore_coordinator.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Wraps the in-process backend so a test can refuse, hold or drop the
/// cancel request.
class _Backend extends http.BaseClient {
  _Backend(this.inner);

  final InProcessMockClient inner;

  /// Called for POST /cancel; return a response to short-circuit it.
  Future<http.StreamedResponse?> Function(http.BaseRequest request)? onCancel;
  int cancelPosts = 0;
  final List<String?> cancelKeys = <String?>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'POST' && request.url.path.endsWith('/cancel')) {
      cancelPosts += 1;
      cancelKeys.add(request.headers['Idempotency-Key']);
      final hook = onCancel;
      if (hook != null) {
        final response = await hook(request);
        if (response != null) return response;
      }
    }
    return inner.send(request);
  }
}

http.StreamedResponse _json(int status, Map<String, dynamic> body) =>
    http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(body))),
      status,
      headers: {'content-type': 'application/json'},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  late InProcessMockClient server;
  late _Backend backend;
  late ApiClient api;
  late MockRideRealtime realtime;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RideSnapshotStore.epoch = 0;
    FindingDriverController.active = null;
    server = InProcessMockClient();
    backend = _Backend(server);
    api = ApiClient(client: backend);
    realtime = MockRideRealtime(assignAfter: const Duration(days: 1), api: api);
    RideRestoreCoordinator.instance.showing = RestoredSurface.home;
  });

  tearDown(() {
    realtime.dispose();
  });

  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() done, {
    int max = 60,
  }) async {
    for (var i = 0; i < max && !done(); i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<GlobalKey<NavigatorState>> openFinding(
    WidgetTester tester,
    String rideId,
  ) async {
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
          home: const Scaffold(body: Center(child: Text('cancel-first-home'))),
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
    return nav;
  }

  Future<void> tapCancelControl(WidgetTester tester) async {
    expect(find.bySemanticsLabel('Cancel request'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Cancel ride?'), findsOneWidget);
  }

  Future<void> confirmCancel(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(TextButton, 'Cancel request'));
    await tester.pump();
  }

  testWidgets('Cancel request commits the cancel before the why-sheet opens', (
    tester,
  ) async {
    const rideId = 'cf-commit-first';
    await openFinding(tester, rideId);
    await tapCancelControl(tester);
    await confirmCancel(tester);
    await pumpUntil(
      tester,
      () => find.text('Why are you cancelling?').evaluate().isNotEmpty,
    );
    await tester.pump(const Duration(milliseconds: 400));

    // The why-sheet is open, and the cancel is already done everywhere.
    expect(find.text('Why are you cancelling?'), findsOneWidget);
    expect(server.rides[rideId]!['status'], 'cancelled_by_rider');
    expect(AppScope.instance.ride.status, RideStatus.cancelledByRider);
    expect(await RideSnapshotStore.read(), isNull);
    expect(await PendingCancelStore.all(), isEmpty);
    final history = await OnDemandRideHistoryStore.read();
    expect(history.single.reservationId, 'ondemand-$rideId');
    expect(backend.cancelPosts, 1);
    expect(backend.cancelKeys.single, isNotNull);

    // A reload now restores Home, not Finding.
    final restore = RideRestoreCoordinator(reader: RideSnapshotStore.read);
    expect(
      restore.surfaceFor(await RideSnapshotStore.read()),
      RestoredSurface.home,
    );

    // Feedback only: no Keep ride, just Skip / Send.
    expect(find.text('Keep ride'), findsNothing);
    expect(find.text('Skip'), findsOneWidget);
    expect(find.text('Send'), findsOneWidget);

    await tester.tap(find.text('Plans changed'));
    await tester.pump();
    await tester.tap(find.text('Send'));
    await pumpUntil(
      tester,
      () =>
          find.text('cancel-first-home').evaluate().isNotEmpty &&
          find.byType(FindingDrivers).evaluate().isEmpty,
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(FindingDrivers), findsNothing);
    expect(find.text('cancel-first-home'), findsOneWidget);
    expect(server.rides[rideId]!['cancellationReason'], isNotNull);
    final archived = await OnDemandRideHistoryStore.read();
    expect(archived, hasLength(1));
    expect(archived.single.cancellationReason, isNotNull);
    expect(AppScope.instance.ride.status, RideStatus.cancelledByRider);
  });

  testWidgets('Skip after a committed cancel still leaves the ride cancelled', (
    tester,
  ) async {
    const rideId = 'cf-skip';
    await openFinding(tester, rideId);
    await tapCancelControl(tester);
    await confirmCancel(tester);
    await pumpUntil(tester, () => find.text('Skip').evaluate().isNotEmpty);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Skip'));
    await pumpUntil(
      tester,
      () => find.byType(FindingDrivers).evaluate().isEmpty,
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(FindingDrivers), findsNothing);
    expect(server.rides[rideId]!['status'], 'cancelled_by_rider');
    expect(server.rides[rideId]!['cancellationReason'], isNull);
    expect(await RideSnapshotStore.read(), isNull);
  });

  testWidgets(
    '409 driver already accepted commits nothing and moves on to Waiting',
    (tester) async {
      const rideId = 'cf-409';
      await openFinding(tester, rideId);
      backend.onCancel = (_) async {
        // The server matched a driver just before the cancel arrived.
        server.rides[rideId] = {
          'id': rideId,
          'status': 'driverAssigned',
          'driver': {'id': 'd1', 'name': 'Sara'},
        };
        return _json(409, {
          'code': 'CONFLICT',
          'message': 'Driver already accepted',
        });
      };
      await tapCancelControl(tester);
      await confirmCancel(tester);
      await pumpUntil(
        tester,
        () => find.byType(WaitingForDriver).evaluate().isNotEmpty,
        max: 80,
      );

      expect(
        find.text(
          'A driver already accepted your ride, so it wasn’t cancelled.',
        ),
        findsOneWidget,
      );
      expect(find.text('Why are you cancelling?'), findsNothing);
      expect(find.byType(WaitingForDriver), findsOneWidget);
      expect(AppScope.instance.ride.status, isNot(RideStatus.cancelledByRider));
      expect(AppScope.instance.ride.status.isMatched, isTrue);
      expect(await OnDemandRideHistoryStore.read(), isEmpty);
      expect(await PendingCancelStore.all(), isEmpty);
      expect((await RideSnapshotStore.read())?.rideId, rideId);

      realtime.dispose();
      await tester.pump(const Duration(seconds: 5));
    },
  );

  testWidgets(
    'a match while "Cancel ride?" is open closes it and nothing is cancelled',
    (tester) async {
      const rideId = 'cf-match-open';
      await openFinding(tester, rideId);
      await tapCancelControl(tester);

      realtime.assignNow();
      await pumpUntil(
        tester,
        () => find.byType(WaitingForDriver).evaluate().isNotEmpty,
        max: 80,
      );

      expect(find.text('Cancel ride?'), findsNothing);
      expect(find.text('A driver accepted your ride.'), findsOneWidget);
      expect(find.byType(WaitingForDriver), findsOneWidget);
      expect(backend.cancelPosts, 0);
      expect(server.rides[rideId]!['status'], isNot('cancelled_by_rider'));
      expect(AppScope.instance.ride.status.isMatched, isTrue);

      realtime.dispose();
      await tester.pump(const Duration(seconds: 5));
    },
  );

  testWidgets(
    'offline: nothing is committed, the search shows Cancelling… and the '
    'outbox keeps the cancel until the server confirms it (RC-03)',
    (tester) async {
      const rideId = 'cf-offline';
      await openFinding(tester, rideId);
      backend.onCancel = (_) async => throw http.ClientException('offline');
      await tapCancelControl(tester);
      await confirmCancel(tester);
      await pumpUntil(
        tester,
        () => find.text('Cancelling your ride…').evaluate().isNotEmpty,
      );
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(FindingDrivers), findsOneWidget);
      expect(find.text('Why are you cancelling?'), findsNothing);
      expect(AppScope.instance.ride.status, RideStatus.findingDriver);
      expect(await OnDemandRideHistoryStore.read(), isEmpty);
      final queued = await PendingCancelStore.all();
      expect(queued.single.rideId, rideId);
      final key = queued.single.idempotencyKey;
      expect(key, isNotNull);
      // Both in-session attempts reused the outbox key.
      expect(backend.cancelKeys, [key, key]);

      // Back online: the outbox sends the same request; the server's answer
      // commits the cancel and only then is the why-sheet offered.
      backend.onCancel = null;
      unawaited(FindingDriverController.flushPendingCancels(api: api));
      await pumpUntil(
        tester,
        () => find.text('Why are you cancelling?').evaluate().isNotEmpty,
      );
      expect(backend.cancelKeys.last, key);
      expect(AppScope.instance.ride.status, RideStatus.cancelledByRider);
      expect(await RideSnapshotStore.read(), isNull);
      expect(await PendingCancelStore.all(), isEmpty);
      expect(server.rides[rideId]!['status'], 'cancelled_by_rider');

      await tester.tap(find.text('Plans changed'));
      await tester.pump();
      await tester.tap(find.text('Send'));
      await pumpUntil(
        tester,
        () => find.byType(FindingDrivers).evaluate().isEmpty,
      );
      await tester.pump(const Duration(milliseconds: 400));
    },
  );

  testWidgets(
    'AUD-3: with the sheet collapsed the chevron never opens Cancel ride?',
    (tester) async {
      await openFinding(tester, 'cf-chevron');
      final chevron = find.bySemanticsLabel('Collapse');
      if (chevron.evaluate().isNotEmpty) {
        await tester.tap(chevron);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(find.text('Cancel ride?'), findsNothing);
      expect(AppScope.instance.ride.status, RideStatus.findingDriver);

      // Cancelling has its own labelled control.
      await tapCancelControl(tester);
      await tester.tap(find.text('Wait for driver'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Cancel ride?'), findsNothing);
      expect(AppScope.instance.ride.status, RideStatus.findingDriver);
      expect(backend.cancelPosts, 0);
    },
  );
}
