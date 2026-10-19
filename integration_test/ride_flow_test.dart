import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:movera_rider/app/app.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/data/finding_driver_repository.dart';
import 'package:movera_rider/features/home/presentation/home.dart';
import 'package:movera_rider/features/ride_booking/application/ride_restore_coordinator.dart';
import 'package:movera_rider/features/ride_booking/application/ride_session.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_booking/presentation/ride_restore_gate.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('boot shows restore gate then material app', (tester) async {
    await tester.pumpWidget(const MoveraApp());
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(RideRestoreGate), findsOneWidget);
  });

  testWidgets('quote then book reaches Finding on mock (no JS hooks)', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final httpClient = InProcessMockClient();
    final api = ApiClient(client: httpClient);
    final quote = await api.post(
      '/api/v1/quotes',
      body: {'rideType': 'economy'},
    );
    final q = quote['quote'] as Map;
    expect(q['id'], q['quoteId']);
    expect(q['currency'], 'SEK');
    expect(q['expiresInSec'], 120);

    final rideId = await AppScope.instance.booking.submitFinding(
      pickupAddress: 'A',
      destinationAddress: 'B',
      pickupLat: 59.3,
      pickupLng: 18.0,
      destinationLat: 59.4,
      destinationLng: 18.1,
      rideType: 'Movera',
      price: 259,
      paymentMethod: 'Apple Pay',
    );
    expect(rideId, isNotEmpty);
    expect(AppScope.instance.ride.status, RideStatus.findingDriver);
    expect(await RideSnapshotStore.read(), isNotNull);
  });

  testWidgets('cancel then late assign stays Home on mock', (tester) async {
    SharedPreferences.setMockInitialValues({});
    RideSnapshotStore.epoch = 0;
    final api = ApiClient(client: InProcessMockClient());
    final rt = MockRideRealtime(assignAfter: const Duration(days: 1), api: api);
    final ride = RideSession()..rideId = 'r-uat';
    var matches = 0;
    final controller = FindingDriverController(
      realtime: rt,
      ride: ride,
      store: FindingDriverRepository(),
      api: api,
    );
    controller.start(
      snapshot: RideSnapshot(
        status: RideStatus.findingDriver,
        savedAt: DateTime.now(),
        pickupAddress: 'A',
        destinationAddress: 'B',
        pickupLat: 59.3,
        pickupLng: 18.0,
        destinationLat: 59.4,
        destinationLng: 18.1,
        rideType: 'Movera',
        price: 259,
        paymentMethod: 'Apple Pay',
        rideId: 'r-uat',
      ),
      onTick: (_) {},
      onMatched: () => matches += 1,
    );
    await controller.cancelSearch();
    rt.assignNow();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(matches, 0);
    expect(await RideSnapshotStore.read(), isNull);
    final page = await RideRestoreCoordinator(
      reader: RideSnapshotStore.read,
    ).root();
    expect(page, isA<Home>());
    controller.dispose();
    rt.dispose();
  });
}
