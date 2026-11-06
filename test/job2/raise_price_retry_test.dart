import 'dart:convert';

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
import 'package:shared_preferences/shared_preferences.dart';

const _env = AppEnv(flavor: AppFlavor.staging, apiBaseUrl: 'https://x.invalid');

/// v0.18.32 fix job 2 L33 (contract.json#bookedRideSeen.versionRetry;
/// owner 2026-11-05 "Split, then fix"): a raise refused as stale is sent
/// once more with the version the 409 carries.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('L33: raise price 409 version_mismatch → one retry with the new '
      'version → 200', () async {
    final raises = <http.Request>[];
    final api = ApiClient(
      env: _env,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/raise-price')) {
          raises.add(request);
          if (raises.length == 1) {
            return http.Response(
              jsonEncode({
                'code': 'version_mismatch',
                'message': 'The trip changed since you last saw it.',
                'retryable': false,
                'projection': {
                  'tripId': 'r1',
                  'status': 'offered',
                  'version': 6,
                },
              }),
              409,
            );
          }
          return http.Response(
            jsonEncode({
              'tripId': 'r1',
              'rideId': 'r1',
              'status': 'searching',
              'version': 7,
              'fare': {'amountMinor': 27900, 'currency': 'SEK'},
              'updatedAt': '2026-10-26T06:00:00Z',
            }),
            200,
          );
        }
        return http.Response(jsonEncode({'code': 'OK', 'vehicles': []}), 200);
      }),
    );
    final rt = MockRideRealtime(assignAfter: const Duration(days: 1));
    final ride = RideSession()..rideId = 'r1';
    ride.observeProjectionVersion('r1', 4);
    final controller = FindingDriverController(
      realtime: rt,
      ride: ride,
      store: FindingDriverRepository(),
      api: api,
      delayedAfter: Duration.zero,
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
        rideId: 'r1',
      ),
      onTick: (_) {},
      onMatched: () {},
    );

    expect(await controller.confirmPriceIncrease(20), isTrue);
    expect(
      [for (final r in raises) jsonDecode(r.body)['expectedVersion']],
      [4, 6],
    );
    expect(
      raises[0].headers['Idempotency-Key'],
      isNot(raises[1].headers['Idempotency-Key']),
    );
    expect(controller.currentPrice, 279);
    controller.dispose();
    rt.dispose();
  });
}
