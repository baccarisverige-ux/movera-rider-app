import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/notifications/push_payload.dart';

/// SUP3-R3: the server's booked-ride pushes to the rider
/// (movera-server src/reservations/service.ts:190-205, kinds
/// reservation_driver_found / _reminder / _no_driver / _no_driver_found,
/// deepLink movera://trips/{tripId}) must open that booked ride on tap
/// (contract riderTripPush.deepLink, Q9 trips/{id} links), not the
/// Notifications list.
void main() {
  for (final kind in [
    'reservation_driver_found',
    'reservation_reminder',
    'reservation_no_driver',
    'reservation_no_driver_found',
  ]) {
    test('$kind tap opens the booked ride', () {
      final payload = PushPayload.fromMap({
        'kind': kind,
        'notificationId': 'ntf_1',
        'deepLink': 'movera://trips/trp_b1',
        'tripId': 'trp_b1',
      });
      expect(payload.routedRideId, 'trp_b1');
      expect(payload.destination, PushDestination.ride);
    });
  }
}
