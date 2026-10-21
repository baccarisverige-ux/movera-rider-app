import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/features/active_ride/application/active_ride_controller.dart';
import 'package:movera_rider/features/history/data/on_demand_ride_history_store.dart';
import 'package:movera_rider/features/history/data/ride_history_repositories.dart';
import 'package:movera_rider/features/reservations/presentation/reservation_format.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// rider-u33: the server's `cancellation.fee` for a Book Now cancel after
/// the free window was never stored, so History said "Cancelled · Booked
/// price 245 kr" with no fee line although 35 kr was charged.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const rideId = 'ride_cancel_fee_1';

  Map<String, dynamic> cancelledRide({Map<String, dynamic>? fee}) => {
    'tripId': rideId,
    'status': 'cancelled_by_rider',
    'fare': {'amountMinor': 24500, 'currency': 'SEK'},
    'cancellation': {
      'actor': 'rider',
      'reasonCode': 'plans_changed',
      'at': '2026-10-21T09:00:00Z',
      'fee': fee,
    },
  };

  ApiClient cancelApi({Map<String, dynamic>? fee}) => ApiClient(
    client: MockClient((request) async {
      return http.Response(
        jsonEncode({'code': 'OK', 'ride': cancelledRide(fee: fee)}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }),
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
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
        pickupAddress: 'Sveavägen 1',
        destinationAddress: 'Stockholm Arlanda Airport',
        pickupLat: 59.34,
        pickupLng: 18.05,
        destinationLat: 59.65,
        destinationLng: 17.93,
        rideType: 'Movera',
        price: 245,
        paymentMethod: 'Apple Pay',
        rideId: rideId,
      ),
    );
  });

  test('the fee the server charged is on the History record', () async {
    final outcome = await ActiveRideController(
      api: cancelApi(fee: {'amountMinor': 3500, 'currency': 'SEK'}),
    ).markCancelled(reasonId: 'plans_changed');

    expect(outcome, RideCancelOutcome.confirmed);
    final record = (await OnDemandRideHistoryStore.read()).single;
    expect(record.cancellationFee, const Money(3500));
    expect(record.endedEarly, isFalse);
    expect(ReservationFormat.historyStatus(record), 'Cancelled · fee 35 kr');
  });

  test('a free cancel records no fee', () async {
    await ActiveRideController(api: cancelApi()).markCancelled();

    final record = (await OnDemandRideHistoryStore.read()).single;
    expect(record.cancellationFee, isNull);
    expect(ReservationFormat.historyStatus(record), 'Cancelled');
  });

  test('server History trips carry their cancel fee too', () async {
    final api = ApiClient(
      client: MockClient((request) async {
        expect(request.url.path, ApiRideHistoryRepository.path);
        return http.Response(
          jsonEncode({
            'trips': [
              {
                ...cancelledRide(fee: {'amountMinor': 3500, 'currency': 'SEK'}),
                'pickup': {
                  'address': 'Sveavägen 1',
                  'lat': 59.34,
                  'lng': 18.05,
                },
                'destination': {
                  'address': 'Arlanda',
                  'lat': 59.65,
                  'lng': 17.93,
                },
                'updatedAt': '2026-10-21T09:00:00Z',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final rides = await ApiRideHistoryRepository(api: api).loadOnDemand();
    expect(rides, hasLength(1));
    expect(rides.single.cancellationFee, const Money(3500));
    expect(
      ReservationFormat.historyStatus(rides.single),
      'Cancelled · fee 35 kr',
    );
  });
}
