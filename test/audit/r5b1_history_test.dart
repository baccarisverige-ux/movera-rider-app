import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/features/history/data/ride_history_repositories.dart';

void main() {
  test('rider-r5-47: a server trip the rider ended early (rated, charged) '
      'is filed as ended early with its fare', () async {
    final api = ApiClient(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'trips': [
              {
                'tripId': 'r5-47',
                'status': 'cancelled_by_rider',
                'ratingStatus': 'pending',
                'fare': {'amountMinor': 3550, 'currency': 'SEK'},
                'cancellation': {'actor': 'rider', 'fee': null},
                'pickup': {'address': 'A', 'lat': 59.34, 'lng': 18.05},
                'destination': {'address': 'B', 'lat': 59.65, 'lng': 17.93},
                'updatedAt': '2026-10-21T09:00:00Z',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    final ride = (await ApiRideHistoryRepository(api: api).loadOnDemand()).single;
    expect(ride.endedEarly, isTrue);
    expect(ride.chargedFare, const Money(3550, 'SEK'));
  });
}
