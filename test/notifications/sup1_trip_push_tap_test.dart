// SUP-1 (fail-before on main 10f02b32): the rider's trip push (contract
// riderTripPush: kind trip_update, deepLink movera://trip/{tripId}) and the
// Ride Check push (kind ride_check, movera-rider://trip/{tripId}) are read as
// "not a ride" -> a tap opens the Notifications list (bell false: empty).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/notifications/push_payload.dart';
import 'package:movera_rider/core/web/web_push_open.dart';

void main() {
  final contract =
      jsonDecode(File('contracts/contract.json').readAsStringSync()) as Map;
  test('trip_update push tap opens the ride', () {
    final spec = contract['riderTripPush'] as Map;
    final payload = pushFromOpenMessage({
      'notificationId': 'ntf_1',
      'kind': spec['kind'],
      'deepLink': (spec['deepLink'] as String).replaceFirst(
        '{tripId}',
        'trp_1',
      ),
    })!;
    expect(payload.destination, PushDestination.ride);
  });
  test('ride_check push tap opens the ride', () {
    final rc = ((contract['onTrip'] as Map)['rideCheck'] as Map)['push'] as Map;
    final payload = pushFromOpenMessage({
      'notificationId': 'ntf_2',
      'kind': rc['kind'],
      'deepLink': (rc['deepLink']['rider'] as String).replaceFirst(
        '{tripId}',
        'trp_1',
      ),
    })!;
    expect(payload.destination, PushDestination.ride);
  });
  test('trip_update push with tripId only (no link) opens the ride', () {
    // Native (FCM) data map of riderTripPush: { kind, tripId, moment }.
    final payload = PushPayload.fromMap({
      'kind': 'trip_update',
      'tripId': 'trp_9',
      'moment': 'driver_arrived',
    });
    expect(payload.destination, PushDestination.ride);
    expect(payload.routedRideId, 'trp_9');
  });
  test('older ride. push with movera://ride/{id} still opens the ride', () {
    final payload = pushFromOpenMessage({
      'kind': 'ride.driver_arrived',
      'deepLink': 'movera://ride/r_7',
    })!;
    expect(payload.routedRideId, 'r_7');
    expect(payload.destination, PushDestination.ride);
  });
  test('a non-ride notice that names a trip still opens Notifications', () {
    final payload = PushPayload.fromMap({
      'kind': 'receipt_ready',
      'tripId': 'trp_3',
      'deepLink': 'movera://trip/trp_3',
    });
    expect(payload.routedRideId, isNull);
    expect(payload.destination, PushDestination.notifications);
  });
}
