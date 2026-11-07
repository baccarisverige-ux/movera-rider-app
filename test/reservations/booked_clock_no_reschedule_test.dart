import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/api_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';

/// SUP3-R2: the Home chrono's 30 s tick (startLiveIfDue) on a SERVER build.
/// A booked ride the app holds as "driver assigned" reaches 2 min before
/// pickup: the clock must change nothing on the server (the server owns the
/// lifecycle; contract bookLater / bookedRideSeen). Today it sends a rider
/// reschedule attempt (POST /quotes kind scheduled, then /reschedule).
void main() {
  const staging = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://api.example.test',
  );
  final pickup = DateTime.now().toUtc().add(const Duration(minutes: 1));

  Map<String, Object?> trip(String status) => {
    'tripId': 'trp_b1',
    'kind': 'scheduled',
    'status': status,
    'version': 4,
    'categoryId': 'economy',
    'scheduledAt': pickup.toIso8601String(),
    'createdAt': '2026-11-07T10:00:00Z',
    'pickup': {'address': 'Sergels torg', 'lat': 59.3326, 'lng': 18.0649},
    'dropoff': {'address': 'Medborgarplatsen', 'lat': 59.3143, 'lng': 18.0735},
    'stops': <Object>[],
    'fare': {'amountMinor': 24200, 'currency': 'SEK'},
    'paymentMethod': 'cash',
    'driver': {'driverId': 'drv_1', 'firstName': 'Ali'},
  };

  test('2 min before pickup the clock sends no rider command for an accepted '
      'booked ride', () async {
    final seen = <String>[];
    final api = ApiClient(
      client: MockClient((request) async {
        seen.add('${request.method} ${request.url.path}');
        if (request.url.path.endsWith('/rider/trips')) {
          return http.Response(
            jsonEncode({
              'items': [trip('accepted')],
              'nextCursor': null,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        // The server refuses a scheduled quote this close to pickup.
        return http.Response(
          jsonEncode({
            'code': 'invalid_request',
            'message': 'Book at least 15 minutes ahead.',
            'reason': 'booking_too_soon',
            'retryable': false,
          }),
          400,
          headers: {'content-type': 'application/json'},
        );
      }),
      env: staging,
    );
    final controller = ReservationController(
      store: ApiReservationRepository(api: api),
      environment: staging,
    );
    await controller.hydrate();
    expect(
      controller.upcoming().single.status,
      ReservationStatus.driverAssigned,
    );
    seen.clear();
    Object? thrown;
    try {
      await controller.startLiveIfDue();
    } catch (error) {
      thrown = error;
    }
    expect(
      seen.where((r) => r.startsWith('POST')).toList(),
      isEmpty,
      reason: 'requests sent by the clock: $seen, error: $thrown',
    );
  });
}
