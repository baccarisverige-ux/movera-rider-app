import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/features/history/data/ride_history_repositories.dart';

/// rider-r5-51: a cancelled server trip is dated by its stable
/// `cancellation.at`, not by `updatedAt`, which a later change moves.
void main() {
  test('a later update does not move a cancelled trip\'s date', () async {
    final api = ApiClient(
      client: MockClient((_) async => http.Response(
            jsonEncode({
              'trips': [
                {
                  'tripId': 'ride_r5_51',
                  'status': 'cancelled_by_rider',
                  'fare': {'amountMinor': 24500, 'currency': 'SEK'},
                  'pickup': {'address': 'A', 'lat': 59.34, 'lng': 18.05},
                  'destination': {'address': 'B', 'lat': 59.65, 'lng': 17.93},
                  'cancellation': {
                    'actor': 'rider',
                    'at': '2026-09-30T21:40:00Z',
                    'fee': {'amountMinor': 3500, 'currency': 'SEK'},
                  },
                  'updatedAt': '2026-10-02T09:00:00Z',
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          )),
    );

    final rides = await ApiRideHistoryRepository(api: api).loadOnDemand();

    expect(
      rides.single.scheduledPickupAt.toUtc(),
      DateTime.utc(2026, 9, 30, 21, 40),
    );
  });
}
