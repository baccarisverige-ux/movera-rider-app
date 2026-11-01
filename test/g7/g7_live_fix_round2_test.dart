import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/config/rider_app_config.dart';
import 'package:movera_rider/core/contracts/matched_driver.dart';
import 'package:movera_rider/core/realtime/api_ride_realtime.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/pickup/presentation/confirm_pickup_spot.dart';
import 'package:movera_rider/features/ride_booking/application/ride_restore_coordinator.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../zone_config/zone_config_fakes.dart';

/// G7 live re-check 2026-11-01, item 1: with `routeChange.beforePickup`
/// off the live build still opened "Change route". The live screens (the
/// restore and the in-app booking) get no `realtime:` and no
/// `pickupMove:`, so these tests build them the same way and put the
/// live transport (contract wire) in the app scope, as the staging build
/// does.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  const rideId = 'g7-live2-trip';
  const driver = MatchedDriver(id: 'drv-1', firstName: 'Ali');
  late RideRealtime savedRealtime;
  late RiderConfigRepository savedConfig;
  late ApiRideRealtime live;

  RideSnapshot snapshot() => RideSnapshot(
    status: RideStatus.driverArriving,
    savedAt: DateTime.now(),
    pickupAddress: 'Sveavägen 1',
    destinationAddress: 'Hornsgatan 2',
    pickupLat: 59.34,
    pickupLng: 18.05,
    destinationLat: 59.31,
    destinationLng: 18.04,
    rideType: 'Movera',
    price: 259,
    paymentMethod: 'Apple Pay',
    rideId: rideId,
    driver: driver,
    version: 4,
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    RideSnapshotStore.epoch = 0;
    FindingDriverController.active = null;
    savedRealtime = AppScope.instance.rideRealtime;
    savedConfig = AppScope.instance.riderConfig;
    final client = MockClient((request) async {
      if (request.method == 'GET' &&
          request.url.path.endsWith('/trips/$rideId')) {
        return http.Response(
          jsonEncode({
            'tripId': rideId,
            'status': 'accepted',
            'version': 5,
            'sequence': 5,
            'updatedAt': '2026-11-01T22:00:00Z',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({
          'code': 'not_found',
          'message': 'no',
          'requestId': 'r',
          'retryable': false,
        }),
        404,
        headers: {'content-type': 'application/json'},
      );
    });
    final api = ApiClient(
      client: client,
      env: const AppEnv(
        flavor: AppFlavor.staging,
        apiBaseUrl: 'https://api.test.invalid',
        authRequired: false,
      ),
    );
    live = ApiRideRealtime(
      api: api,
      followStream: false,
      pollInterval: const Duration(minutes: 5),
    );
    AppScope.instance.rideRealtime = live;
    AppScope.instance.riderConfig = EditedZoneConfigs({
      'Z001': {
        'routeChange': {'on': true, 'beforePickup': false},
      },
    });
    AppScope.instance.ride
      ..rideId = null
      ..suppressRestore = false
      ..restoreFromBackend(RideStatus.driverArriving, id: rideId)
      ..authoritativeVersion = 4;
    await RideSnapshotStore.save(snapshot());
  });

  tearDown(() {
    AppScope.instance.rideRealtime = savedRealtime;
    AppScope.instance.riderConfig = savedConfig;
    live.dispose();
  });

  Future<void> show(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        home: const Scaffold(body: Text('home')),
      ),
    );
    nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => page));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
  }

  // The restore builds the screen the live way (no realtime, no pickupMove).
  Widget restored() {
    final page = RideRestoreCoordinator.instance.pageFor(snapshot());
    expect(page, isA<WaitingForDriver>());
    final waiting = page as WaitingForDriver;
    expect(waiting.realtime, isNull);
    expect(waiting.pickupMove, isNull);
    return waiting;
  }

  // The in-app booking (select ride → FindingDrivers → WaitingForDriver)
  // passes FindingDrivers' `realtime`, which the booking leaves null.
  Widget booked() => const WaitingForDriver(
    pickupAddress: 'Sveavägen 1',
    destinationAddress: 'Hornsgatan 2',
    pickupPosition: LatLng(59.34, 18.05),
    destinationPosition: LatLng(59.31, 18.04),
    rideType: 'Movera',
    price: 259,
    paymentMethod: 'Apple Pay',
    driver: driver,
    rideId: rideId,
  );

  for (final (name, build) in [
    ('restore', restored),
    ('in-app booking', booked),
  ]) {
    group('$name, beforePickup off', () {
      testWidgets('ride card dots open the pickup move, not Change route', (
        tester,
      ) async {
        await show(tester, build());
        await tester.tap(find.byTooltip('Ride details').first);
        await tester.pumpAndSettle();
        expect(find.byType(ConfirmPickupSpot), findsOneWidget);
        expect(find.text('Change route'), findsNothing);
      });

      testWidgets('driver card dots open the pickup move', (tester) async {
        await show(tester, build());
        await tester.tap(find.bySemanticsLabel('More options').first);
        await tester.pumpAndSettle();
        expect(find.byType(ConfirmPickupSpot), findsOneWidget);
        expect(find.text('Change route'), findsNothing);
      });

      testWidgets('cancel sheet: no Change route', (tester) async {
        await show(tester, build());
        await tester.tap(find.byIcon(Icons.close_rounded));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancel request'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Destination needs to be changed'));
        await tester.pumpAndSettle();
        final change = find.byKey(const ValueKey('cancel-change-destination'));
        if (change.evaluate().isNotEmpty) {
          await tester.ensureVisible(change);
          await tester.pumpAndSettle();
          await tester.tap(change);
          await tester.pumpAndSettle();
          expect(
            find.text('You can change the route once you are in the car.'),
            findsOneWidget,
          );
        }
        expect(find.text('Change route'), findsNothing);
      });
    });
  }

  testWidgets('restore, beforePickup on: ride card dots open Change route', (
    tester,
  ) async {
    AppScope.instance.riderConfig = EditedZoneConfigs({
      'Z001': {
        'routeChange': {'on': true, 'beforePickup': true},
      },
    });
    await show(tester, restored());
    await tester.tap(find.byTooltip('Ride details').first);
    await tester.pumpAndSettle();
    expect(find.text('Change route'), findsWidgets);
    expect(find.byType(ConfirmPickupSpot), findsNothing);
  });
}
