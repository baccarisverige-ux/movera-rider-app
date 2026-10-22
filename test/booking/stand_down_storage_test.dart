import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/booking/application/booking_coordinator.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/data/finding_driver_repository.dart';
import 'package:movera_rider/features/ride_booking/application/ride_session.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// rider-r5-32: a duplicate-ride stand-down whose outbox cannot be stored
/// still sends the cancel and does not fail the booking.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the cancel is sent when the outbox write throws', () async {
    // Storage that throws on every outbox read and write.
    SharedPreferences.setMockInitialValues({'movera_pending_cancels': 'x'});
    RideSnapshotStore.epoch = 0;
    var cancels = 0;
    final api = ApiClient(
      env: const AppEnv(
        flavor: AppFlavor.staging,
        apiBaseUrl: 'https://x.invalid',
      ),
      client: MockClient((request) async {
        if (request.url.path.endsWith('/cancel')) cancels++;
        return http.Response(jsonEncode({'code': 'OK', 'vehicles': []}), 200);
      }),
    );
    final owner = FindingDriverController(
      realtime: MockRideRealtime(assignAfter: const Duration(days: 1)),
      ride: RideSession()..rideId = 'ride_owner',
      store: FindingDriverRepository(),
      api: api,
      delayedAfter: Duration.zero,
    );
    owner.start(
      snapshot: RideSnapshot(
        status: RideStatus.findingDriver,
        savedAt: DateTime.now(),
        pickupAddress: 'A',
        destinationAddress: 'B',
        pickupLat: 59.33,
        pickupLng: 18.06,
        destinationLat: 59.34,
        destinationLng: 18.07,
        rideType: 'Movera',
        price: 259,
        paymentMethod: 'Apple Pay',
        rideId: 'ride_owner',
      ),
      onTick: (_) {},
      onMatched: () {},
    );
    FindingDriverController.active = owner;
    addTearDown(() {
      FindingDriverController.active = null;
      owner.dispose();
    });

    final kept = await BookingCoordinator(api: api)
        .reconcileCreatedFinding('ride_duplicate');

    expect(kept, 'ride_owner');
    expect(cancels, 1);
  });
}
