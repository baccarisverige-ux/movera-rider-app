import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/data/finding_driver_repository.dart';
import 'package:movera_rider/features/ride_booking/application/ride_session.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/wallet/data/wallet_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// rider-r5-16: a wallet-paid trip's offer is not raised above the wallet
/// balance, as Select Ride refuses the wallet for a fare above it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a raise the wallet cannot pay is refused', () async {
    SharedPreferences.setMockInitialValues({WalletStore.balanceKey: 260.0});
    var patches = 0;
    final api = ApiClient(
      env: const AppEnv(
        flavor: AppFlavor.staging,
        apiBaseUrl: 'https://x.invalid',
      ),
      client: MockClient((request) async {
        if (request.method == 'PATCH') patches++;
        return http.Response('{"code":"OK","vehicles":[]}', 200);
      }),
    );
    final controller = FindingDriverController(
      realtime: MockRideRealtime(assignAfter: const Duration(days: 1)),
      ride: RideSession()..rideId = 'ride_r5_16',
      store: FindingDriverRepository(),
      api: api,
      delayedAfter: Duration.zero,
    );
    addTearDown(controller.dispose);
    controller.start(
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
        paymentMethod: 'Movera Wallet',
        paymentMethodId: 'wallet',
        rideId: 'ride_r5_16',
      ),
      onTick: (_) {},
      onMatched: () {},
    );

    expect(await controller.confirmPriceIncrease(20), isFalse);
    expect(patches, 0);
  });
}
