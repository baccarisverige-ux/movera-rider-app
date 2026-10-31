import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/active_ride/application/pickup_move_controller.dart';
import 'package:movera_rider/features/ride_booking/application/ride_session.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Driver group 5, status item 4 (contract v0.18.7 `pickupWaiting.pickupMove`):
/// the rider moves the pickup with `PATCH /trips/{tripId} { expectedVersion,
/// pickup }`; the limit is the zone's `booking.maxPickupMoveMeters` (default
/// 200, the admin can change it) from the BOOKED pickup; the server's
/// `pickup_move_too_far` / `pickup_fixed_after_arrival` are shown in plain
/// words in sv / fr / en.
void main() {
  const live = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://x.invalid',
  );
  const booked = GeoPoint(59.3293, 18.0686);
  // About 150 m north of the booked pickup.
  const near = GeoPoint(59.33065, 18.0686);
  // About 450 m north.
  const far = GeoPoint(59.33335, 18.0686);

  tearDown(() => L10n.use('en'));

  test(
    'within the limit: PATCH with expectedVersion and the new pickup',
    () async {
      final requests = <http.Request>[];
      final session = RideSession()..observeProjectionVersion('trp_1', 4);
      final api = ApiClient(
        env: live,
        client: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode({
              'tripId': 'trp_1',
              'status': 'driver_to_pickup',
              'version': 5,
              'pickup': {
                'address': 'Vasagatan 9',
                'lat': 59.33065,
                'lng': 18.0686,
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final controller = PickupMoveController(api: api, session: session);
      final projection = await controller.move(
        tripId: 'trp_1',
        address: 'Vasagatan 9',
        to: near,
        bookedPickup: booked,
        maxMeters: 200,
      );
      final sent = requests.single;
      expect(sent.method, 'PATCH');
      expect(sent.url.path, '/api/v1/trips/trp_1');
      final body = jsonDecode(sent.body) as Map<String, dynamic>;
      expect(body['expectedVersion'], 4);
      expect(body['pickup'], {
        'address': 'Vasagatan 9',
        'lat': 59.33065,
        'lng': 18.0686,
      });
      expect(body.containsKey('dropoff'), isFalse);
      expect(body.containsKey('routeQuoteId'), isFalse);
      expect(projection['version'], 5);
      expect(session.projectionVersionOf('trp_1'), 5);
    },
  );

  test('too far for the zone limit: refused before anything is sent', () async {
    var sent = 0;
    final api = ApiClient(
      env: live,
      client: MockClient((_) async {
        sent += 1;
        return http.Response('{}', 200);
      }),
    );
    final controller = PickupMoveController(api: api);
    await expectLater(
      controller.move(
        tripId: 'trp_1',
        address: 'Far away',
        to: far,
        bookedPickup: booked,
        maxMeters: 200,
      ),
      throwsA(
        isA<PickupMoveException>()
            .having((e) => e.failure, 'failure', PickupMoveFailure.tooFar)
            .having((e) => e.maxMeters, 'maxMeters', 200)
            .having(
              (e) => e.message,
              'message',
              'You can move the pickup at most 200 m. Cancel and book again for another place.',
            ),
      ),
    );
    expect(sent, 0);
    // The admin raised the limit to 500 m: the same move passes the check.
    expect(
      PickupMoveController.check(bookedPickup: booked, to: far, maxMeters: 500),
      isNull,
    );
  });

  test(
    'the server refuses pickup_move_too_far with its own limit (sv)',
    () async {
      L10n.use('sv');
      final api = ApiClient(
        env: live,
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'code': 'invalid_request',
              'reason': 'pickup_move_too_far',
              'message': 'too far',
              'details': ['maxMeters=150', 'meters=180'],
            }),
            400,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      final controller = PickupMoveController(api: api);
      await expectLater(
        controller.move(tripId: 'trp_1', address: 'x', to: near),
        throwsA(
          isA<PickupMoveException>().having(
            (e) => e.message,
            'message',
            'Du kan flytta upphämtningen högst 150 m. Avboka och boka om för en annan plats.',
          ),
        ),
      );
    },
  );

  test('after the driver arrived the pickup is fixed (fr)', () async {
    L10n.use('fr');
    final api = ApiClient(
      env: live,
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'code': 'invalid_transition',
            'reason': 'pickup_fixed_after_arrival',
            'message': 'fixed',
            'projection': {
              'tripId': 'trp_1',
              'status': 'arrived',
              'version': 7,
            },
          }),
          409,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    final session = RideSession();
    final controller = PickupMoveController(api: api, session: session);
    await expectLater(
      controller.move(tripId: 'trp_1', address: 'x', to: near),
      throwsA(
        isA<PickupMoveException>()
            .having(
              (e) => e.failure,
              'failure',
              PickupMoveFailure.fixedAfterArrival,
            )
            .having(
              (e) => e.message,
              'message',
              'Le chauffeur est déjà là – le point de départ ne peut plus être déplacé',
            ),
      ),
    );
    expect(
      session.projectionVersionOf('trp_1'),
      7,
      reason: 'the 409 carries the current trip',
    );
  });

  test('a version mismatch tells the rider the ride just changed', () async {
    final api = ApiClient(
      env: live,
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'code': 'version_mismatch',
            'message': 'stale',
            'projection': {
              'tripId': 'trp_1',
              'status': 'driver_to_pickup',
              'version': 9,
            },
          }),
          409,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    await expectLater(
      PickupMoveController(
        api: api,
      ).move(tripId: 'trp_1', address: 'x', to: near),
      throwsA(
        isA<PickupMoveException>().having(
          (e) => e.failure,
          'failure',
          PickupMoveFailure.stale,
        ),
      ),
    );
  });
}
