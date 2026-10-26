import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/features/active_ride/application/active_ride_controller.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/wallet/data/wallet_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// rider-r5-12: a cancel fee on a wallet-paid trip is debited from the
/// local wallet, as History says it was paid by Movera Wallet.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const rideId = 'ride_r5_12';

  test('a wallet ride\'s cancel fee leaves the wallet', () async {
    SharedPreferences.setMockInitialValues({WalletStore.balanceKey: 100.0});
    RideSnapshotStore.epoch = 0;
    AppScope.instance.ride
      ..rideId = null
      ..suppressRestore = false
      ..authoritativeVersion = null
      ..authoritativeUpdatedAt = null
      ..restoreFromBackend(RideStatus.driverArriving, id: rideId);
    await RideSnapshotStore.save(
      RideSnapshot(
        status: RideStatus.driverArriving,
        savedAt: DateTime.now(),
        pickupAddress: 'A',
        destinationAddress: 'B',
        pickupLat: 59.34,
        pickupLng: 18.05,
        destinationLat: 59.65,
        destinationLng: 17.93,
        rideType: 'Movera',
        price: 245,
        paymentMethod: 'Movera Wallet',
        paymentMethodId: 'wallet',
        rideId: rideId,
      ),
    );
    final api = ApiClient(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'code': 'OK',
            'ride': {
              'tripId': rideId,
              'status': 'cancelled_by_rider',
              'fare': {'amountMinor': 24500, 'currency': 'SEK'},
              'cancellation': {
                'actor': 'rider',
                'reasonCode': 'plans_changed',
                'fee': {'amountMinor': 3500, 'currency': 'SEK'},
              },
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );

    await ActiveRideController(
      api: api,
    ).markCancelled(reasonId: 'plans_changed');

    expect(await WalletStore().loadBalance(), 65);
  });
}
