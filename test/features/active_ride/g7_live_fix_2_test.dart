import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/router/routes.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/config/rider_app_config.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/active_ride/application/active_ride_controller.dart';
import 'package:movera_rider/features/active_ride/application/pickup_move_controller.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/safety/domain/ride_check_trigger.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../zone_config/zone_config_fakes.dart';

/// G7 live test 2026-11-01, checker round 2.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('dropped far uses the zone rideCheck.endFarMeters', () {
    // The server sends no finishFarFromDropoffKm any more: 3 km before.
    const base = RideCheckTriggerSettings();

    test('SE zone 800 m: 1 km from the drop-off asks, 700 m does not', () {
      final zone = SeedRiderConfigRepository.seed;
      final config = RiderAppConfig.fromJson({
        ...SeedRiderConfigRepository.seedDocument,
        'rideCheck': {...zone.rideCheck, 'endFarMeters': 800},
      })!;
      final settings = base.withZoneRideCheck(config.rideCheck);
      expect(settings.finishFarFromDropoffKm, 0.8);
      expect(settings.finishedFarFromDropoff(1000), isTrue);
      expect(settings.finishedFarFromDropoff(700), isFalse);
      // Without the zone the old fallback missed it.
      expect(base.finishedFarFromDropoff(1000), isFalse);
    });

    test('FR zone 500 m: 600 m asks', () {
      final settings = base.withZoneRideCheck({'endFarMeters': 500});
      expect(settings.finishFarFromDropoffKm, 0.5);
      expect(settings.finishedFarFromDropoff(600), isTrue);
    });

    test('a missing or bad value keeps the settings', () {
      expect(base.withZoneRideCheck(null).finishFarFromDropoffKm, 3);
      expect(
        base.withZoneRideCheck({'endFarMeters': -1}).finishFarFromDropoffKm,
        3,
      );
    });
  });

  group('three dots with routeChange.beforePickup off', () {
    test('the pickup still moves while the driver is on the way', () {
      expect(
        WaitingForDriver.detailsAction(
          beforePickupOff: true,
          pickupEditable: true,
        ),
        DetailsAction.movePickup,
      );
    });

    test('after the driver arrived nothing is left to change', () {
      expect(
        WaitingForDriver.detailsAction(
          beforePickupOff: true,
          pickupEditable: false,
        ),
        DetailsAction.refused,
      );
    });

    test('switch on: the route screen opens', () {
      expect(
        WaitingForDriver.detailsAction(
          beforePickupOff: false,
          pickupEditable: true,
        ),
        DetailsAction.routeScreen,
      );
    });
  });

  group('cancel sheet "Change destination" reads the switch again', () {
    late InProcessMockClient server;
    late RiderConfigRepository savedConfig;

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      server = InProcessMockClient();
      RideSnapshotStore.epoch = 0;
      FindingDriverController.active = null;
      savedConfig = AppScope.instance.riderConfig;
      AppScope.instance.ride
        ..rideId = null
        ..suppressRestore = false
        ..restoreFromBackend(RideStatus.idle);
    });
    tearDown(() => AppScope.instance.riderConfig = savedConfig);

    testWidgets('switched off after the screen opened: refused, no editor', (
      tester,
    ) async {
      const rideId = 'g7-cancel-change-dest';
      server.rides[rideId] = {'id': rideId, 'status': 'accepted'};
      AppScope.instance.ride.restoreFromBackend(
        RideStatus.driverAssigned,
        id: rideId,
      );
      await RideSnapshotStore.save(
        RideSnapshot(
          status: RideStatus.driverAssigned,
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
        ),
      );
      // On when the screen opens.
      AppScope.instance.riderConfig = EditedZoneConfigs();
      final realtime = MockRideRealtime(assignAfter: const Duration(days: 1))
        ..primeResume(status: RideStatus.driverAssigned);
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          home: const Scaffold(body: Text('home')),
        ),
      );
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
            controller: ActiveRideController(api: ApiClient(client: server)),
            pickupMove: PickupMoveController(api: ApiClient(client: server)),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();
      // The admin turns it off meanwhile.
      AppScope.instance.riderConfig = EditedZoneConfigs({
        'Z001': {
          'routeChange': {'on': true, 'beforePickup': false},
        },
      });

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel request'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Destination needs to be changed'));
      await tester.pumpAndSettle();
      final change = find.byKey(const ValueKey('cancel-change-destination'));
      await tester.ensureVisible(change);
      await tester.pumpAndSettle();
      await tester.tap(change);
      await tester.pumpAndSettle();

      expect(
        find.text('You can change the route once you are in the car.'),
        findsOneWidget,
      );
      expect(find.text('Change route'), findsNothing);
      expect(find.byType(WaitingForDriver), findsOneWidget);
      expect(server.rides[rideId]!['status'], 'accepted');
      realtime.dispose();
    });
  });
}
