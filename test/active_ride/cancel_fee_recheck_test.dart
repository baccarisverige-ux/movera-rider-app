import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/router/routes.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/active_ride/application/active_ride_controller.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// rider-r5-11: when the free window closes while the cancel sheets are
/// open, the rider is asked again with the fee instead of being charged
/// on the "free" answer.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  tearDown(() => WaitingForDriver.cancelFeeClock = DateTime.now);

  testWidgets('a fee that starts mid-flow is shown before sending', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final server = InProcessMockClient();
    RideSnapshotStore.epoch = 0;
    FindingDriverController.active = null;
    const rideId = 'r5-11-ride';
    server.rides[rideId] = {'id': rideId, 'status': 'accepted'};
    AppScope.instance.ride
      ..rideId = null
      ..suppressRestore = false
      ..restoreFromBackend(RideStatus.driverAssigned, id: rideId);
    var offset = const Duration(seconds: 80);
    WaitingForDriver.cancelFeeClock = () => DateTime.now().add(offset);
    final realtime = MockRideRealtime(assignAfter: const Duration(days: 1))
      ..primeResume(status: RideStatus.driverAssigned);
    await tester.pumpWidget(MaterialApp(
      home: WaitingForDriver(
        pickupAddress: 'Sveavägen 1',
        destinationAddress: 'Hornsgatan 2',
        pickupPosition: const LatLng(59.34, 18.05),
        destinationPosition: const LatLng(59.31, 18.04),
        rideType: 'Movera',
        categoryId: 'economy',
        price: 259,
        paymentMethod: 'Apple Pay',
        rideId: rideId,
        realtime: realtime,
        controller: ActiveRideController(api: ApiClient(client: server)),
      ),
      onGenerateRoute: (s) => MaterialPageRoute<void>(
        settings: const RouteSettings(name: AppRoutes.waitingForDriver),
        builder: (_) => const SizedBox(),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.textContaining('less than a minute'), findsOneWidget);
    offset = const Duration(seconds: 150);
    await tester.tap(find.text('Cancel request'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Driver/ride details are not suitable'));
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel ride'));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.textContaining('Cancelling now costs'), findsOneWidget);
    expect(server.rides[rideId]!['status'], 'accepted');
    realtime.dispose();
    await tester.pump(const Duration(seconds: 1));
  });
}
