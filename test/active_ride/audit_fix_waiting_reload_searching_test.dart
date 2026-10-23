import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/contracts/matched_driver.dart';
import 'package:movera_rider/core/realtime/api_ride_realtime.dart';
import 'package:movera_rider/features/active_ride/application/active_ride_controller.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Audit 2026-10-21 (rider-26): the driver drops the ride and the rider
/// reloads before the next driver accepts. The stored ride still names the
/// dropped driver, so Waiting is restored; the server's first answer is
/// `searching`. Waiting must go back to the search instead of showing the
/// old driver "on the way" over a trip that is being re-dispatched.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const rideId = 'reload-searching';
  const t0 = '2026-10-23T09:00:00Z';

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    RideSnapshotStore.epoch = 0;
  });

  testWidgets('a restored Waiting that is told searching goes back to the search',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var polls = 0;
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path.endsWith('/rides/$rideId')) {
        polls += 1;
        return http.Response(
          jsonEncode({
            'tripId': rideId,
            'status': 'searching',
            'version': 5,
            'sequence': 5,
            'updatedAt': t0,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({'code': 'not_found', 'message': 'no', 'requestId': 'r', 'retryable': false}),
        404,
        headers: {'content-type': 'application/json'},
      );
    });
    final api = ApiClient(client: client, env: AppEnv.current);
    final realtime = ApiRideRealtime(api: api, pollInterval: const Duration(seconds: 2));
    addTearDown(realtime.dispose);

    // The device copy from before the reload: the dropped driver on the way.
    const driver = MatchedDriver(id: 'drv-old', firstName: 'Ali');
    await RideSnapshotStore.save(RideSnapshot(
      status: RideStatus.driverArriving,
      savedAt: DateTime.now(),
      pickupAddress: 'Stockholm pickup',
      destinationAddress: 'Stockholm destination',
      pickupLat: 59.3293,
      pickupLng: 18.0686,
      destinationLat: 59.3326,
      destinationLng: 18.0649,
      rideType: 'Movera',
      price: 259,
      paymentMethod: 'Apple Pay',
      rideId: rideId,
      driver: driver,
      version: 4,
    ));
    AppScope.instance.ride
      ..restoreFromBackend(RideStatus.driverArriving, id: rideId)
      ..authoritativeVersion = 4;

    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: Center(child: Text('audit-root'))),
      ),
    );
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => WaitingForDriver(
          pickupAddress: 'Stockholm pickup',
          destinationAddress: 'Stockholm destination',
          pickupPosition: const LatLng(59.3293, 18.0686),
          destinationPosition: const LatLng(59.3326, 18.0649),
          rideType: 'Movera',
          price: 259,
          paymentMethod: 'Apple Pay',
          driver: driver,
          rideId: rideId,
          realtime: realtime,
          controller: ActiveRideController(api: api),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(WaitingForDriver), findsOneWidget);

    // The first poll says searching.
    for (var i = 0; i < 60 && find.byType(WaitingForDriver).evaluate().isNotEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(polls, greaterThan(0), reason: 'the server was asked');
    expect(find.byType(WaitingForDriver), findsNothing,
        reason: 'Waiting leaves when the trip is back in dispatch');
    expect(AppScope.instance.ride.status, RideStatus.findingDriver);
  });
}
