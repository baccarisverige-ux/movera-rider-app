import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/contracts/cancel_reasons.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';

/// X7: the stand-in server enforces the command contract, not only the
/// transition table: `expectedVersion` (409 version_mismatch with the
/// projection), reason codes per actor, and the rider cancel fee from the
/// rider config (contract §1, §3, §6). RC-08: the mock realtime re-arms
/// assignment for a search that subscribes again.
void main() {
  late InProcessMockClient server;
  late ApiClient api;
  var now = DateTime.utc(2026, 10, 19, 8);

  setUp(() {
    now = DateTime.utc(2026, 10, 19, 8);
    server = InProcessMockClient(clock: () => now);
    api = ApiClient(client: server);
  });

  Future<Map<String, dynamic>> book({String category = 'economy'}) async {
    final quote = (await api.post(
      '/api/v1/quotes',
      body: {
        'rideType': category,
        'pickupLat': 59.3293,
        'pickupLng': 18.0686,
        'destinationLat': 59.3326,
        'destinationLng': 18.0649,
      },
    ))['quote'] as Map;
    final created = await api.post(
      '/api/v1/rides',
      body: {
        'categoryId': category,
        'price': (quote['totalMinor'] as int) / 100,
        'paymentMethodId': 'cash',
        'pickupAddress': 'Pickup',
        'destinationAddress': 'Destination',
        'pickupLat': 59.3293,
        'pickupLng': 18.0686,
        'destinationLat': 59.3326,
        'destinationLng': 18.0649,
        'quoteId': quote['id'],
        'quoteSignedPayload': quote['signedPayload'],
        'quoteExpiresAt': quote['expiresAt'],
        'quoteTotalMinor': quote['totalMinor'],
      },
    );
    return Map<String, dynamic>.from(created['ride'] as Map);
  }

  Future<Map<String, dynamic>> simulate(String id, Map<String, dynamic> body) async =>
      Map<String, dynamic>.from(
        (await api.post('/api/v1/rides/$id/status', body: body))['ride'] as Map,
      );

  Future<ApiError> refused(Future<Object?> call) async {
    try {
      await call;
    } on ApiError catch (error) {
      return error;
    }
    fail('expected an ApiError');
  }

  // openapi CancelCommand requires a reasonCode (rider-u19); a rider who
  // picked none sends the unspecified one, as the app does.
  Future<Map<String, dynamic>> cancel(
    String id, {
    Map<String, dynamic>? body,
    String path = 'cancel',
  }) async =>
      Map<String, dynamic>.from(
        (await api.post(
          '/api/v1/rides/$id/$path',
          body: body ??
              (path == 'cancel' ? CancelReasonCodes.riderCancelBody(null) : {}),
        ))['ride'] as Map,
      );

  group('expectedVersion', () {
    test('a stale version is 409 version_mismatch and changes nothing',
        () async {
      final ride = await book();
      final id = ride['id'] as String;
      final accepted = await simulate(id, {'status': 'accepted'});
      final current = accepted['version'] as int;

      final error = await refused(api.post(
        '/api/v1/rides/$id/cancel',
        body: {'expectedVersion': current - 2, 'reasonCode': 'plans_changed'},
      ));
      expect(error.statusCode, 409);
      expect(error.code, 'version_mismatch');
      expect(error.isVersionMismatch, isTrue);
      final stored = server.rides[id]!;
      expect(stored['status'], 'accepted');
      expect(stored['version'], current);
      expect(stored['cancellation'], isNull);
    });

    test('the current version is accepted; none at all still is', () async {
      final first = await book();
      final firstId = first['id'] as String;
      final ok = await cancel(
        firstId,
        body: {'expectedVersion': first['version'], 'reasonCode': 'plans_changed'},
      );
      expect(ok['status'], 'cancelled_by_rider');

      final second = await book();
      expect(
        (await cancel(second['id'] as String))['status'],
        'cancelled_by_rider',
      );
    });

    test('a stale simulated driver command is refused too', () async {
      final ride = await book();
      final id = ride['id'] as String;
      final error = await refused(api.post(
        '/api/v1/rides/$id/status',
        body: {'command': 'send_offer', 'actor': 'system', 'expectedVersion': 99},
      ));
      expect(error.code, 'version_mismatch');
      expect(server.rides[id]!['status'], 'searching');
    });
  });

  group('reason codes per actor', () {
    test('a rider cannot cancel with an admin code', () async {
      final ride = await book();
      final id = ride['id'] as String;
      final error = await refused(api.post(
        '/api/v1/rides/$id/cancel',
        body: {'reasonCode': 'admin_fraud'},
      ));
      expect(error.statusCode, 400);
      expect(error.code, 'invalid_request');
      expect(server.rides[id]!['status'], 'searching');
      expect(server.rides[id]!['cancellation'], isNull);
    });

    test('a late reason after the cancel is checked as well', () async {
      final ride = await book();
      final id = ride['id'] as String;
      await cancel(id);
      // Owner decision 6 (v0.4.4): the late reason is its own command.
      final error = await refused(api.post(
        '/api/v1/trips/$id/cancel-reason',
        body: {'reasonCode': 'system_error'},
      ));
      expect(error.code, 'invalid_request');
      expect(
        (server.rides[id]!['cancellation'] as Map)['reasonCode'],
        CancelReasonCodes.unspecified,
      );
      final late = (await api.post(
        '/api/v1/trips/$id/cancel-reason',
        body: {'reasonCode': 'wait_too_long'},
      ))['ride'] as Map;
      expect((late['cancellation'] as Map)['reasonCode'], 'wait_too_long');
    });

    test('a legacy free-text reason is kept but is not a reasonCode',
        () async {
      final ride = await book();
      final cancelled = await cancel(
        ride['id'] as String,
        body: CancelReasonCodes.riderCancelBody('changed-plans'),
      );
      expect(cancelled['cancellationReason'], 'changed-plans');
      expect(
        (cancelled['cancellation'] as Map)['reasonCode'],
        CancelReasonCodes.unspecified,
      );
    });

    test('a driver cancel takes driver codes only', () async {
      final ride = await book();
      final id = ride['id'] as String;
      await simulate(id, {'status': 'accepted'});
      final error = await refused(api.post(
        '/api/v1/rides/$id/status',
        body: {
          'command': 'cancel',
          'actor': 'driver',
          'reasonCode': 'plans_changed',
        },
      ));
      expect(error.code, 'invalid_request');
      expect(server.rides[id]!['status'], 'accepted');

      final admin = await simulate(id, {
        'command': 'cancel',
        'actor': 'admin',
        'reasonCode': 'admin_safety',
      });
      expect(admin['status'], 'cancelled_by_admin');
      expect((admin['cancellation'] as Map)['reasonCode'], 'admin_safety');
    });
  });

  group('rider cancel fee (contract §6)', () {
    Map<String, dynamic>? feeOf(Map<String, dynamic> ride) =>
        (ride['cancellation'] as Map)['fee'] as Map<String, dynamic>?;

    test('free while searching: no driver accepted yet', () async {
      final ride = await book();
      now = now.add(const Duration(minutes: 30));
      expect(feeOf(await cancel(ride['id'] as String)), isNull);
    });

    test('live economy: free for 2 min after accept, then 35 kr', () async {
      final early = await book();
      await simulate(early['id'] as String, {'status': 'accepted'});
      now = now.add(const Duration(seconds: 90));
      expect(feeOf(await cancel(early['id'] as String)), isNull);

      final late = await book();
      await simulate(late['id'] as String, {'status': 'driver_to_pickup'});
      now = now.add(const Duration(minutes: 2));
      expect(feeOf(await cancel(late['id'] as String)), {
        'amountMinor': 3500,
        'currency': 'SEK',
      });
    });

    test('live premium: 15% of the fare, clamped to the rule', () async {
      final ride = await book(category: 'premium');
      final fare = (ride['fare'] as Map)['amountMinor'] as int;
      await simulate(ride['id'] as String, {'status': 'arrived'});
      now = now.add(const Duration(minutes: 5));
      final fee = feeOf(await cancel(ride['id'] as String))!;
      final expected = ((fare * 15 * 2 + 100) ~/ 200).clamp(5000, 15000);
      expect(fee['amountMinor'], expected);
    });

    test('a driver drop restarts the free window', () async {
      final ride = await book();
      final id = ride['id'] as String;
      await simulate(id, {'status': 'accepted'});
      now = now.add(const Duration(minutes: 10));
      await simulate(id, {'command': 'cancel', 'actor': 'driver'});
      expect(server.rides[id]!['status'], 'searching');
      expect(feeOf(await cancel(id)), isNull);
    });

    test('end-early carries no cancel fee: the rider pays the fare',
        () async {
      final ride = await book();
      final id = ride['id'] as String;
      await simulate(id, {'status': 'in_trip'});
      now = now.add(const Duration(minutes: 10));
      final ended = await cancel(id, path: 'end-early');
      expect(ended['status'], 'cancelled_by_rider');
      expect(feeOf(ended), isNull);
      expect(ended['fare'], isNotNull);
    });

    test('scheduled: the reservation rule of the category, to pickup',
        () async {
      final ride = await book(category: 'premium');
      final id = ride['id'] as String;
      final stored = server.rides[id]!;
      final pickup = now.add(const Duration(minutes: 90));
      stored['kind'] = 'scheduled';
      stored['scheduledAt'] = pickup.toIso8601String();
      stored['driver'] = {'name': 'Driver'};
      final fare = (stored['fare'] as Map)['amountMinor'] as int;
      final fee = feeOf(await cancel(id))!;
      // Premium reservation: free until 120 min before, then 25%, 80–300 kr.
      expect(
        fee['amountMinor'],
        ((fare * 25 * 2 + 100) ~/ 200).clamp(8000, 30000),
      );
    });
  });

  test('RC-08 a search that subscribes again still gets a driver', () async {
    final realtime = MockRideRealtime(
      assignAfter: const Duration(milliseconds: 50),
    );
    addTearDown(realtime.dispose);
    final seen = <RideStatus>[];
    final first = realtime.subscribe('ride-x').listen((e) => seen.add(e.status));
    await Future<void>.delayed(Duration.zero);
    expect(seen, [RideStatus.findingDriver],
        reason: 'the first status reaches the listener');
    await first.cancel();
    realtime.unsubscribe();
    final second =
        realtime.subscribe('ride-x').listen((e) => seen.add(e.status));
    addTearDown(second.cancel);
    // Waits on the assignment itself (10 ms steps, 5 s at most), so a
    // loaded machine does not fail it before the 50 ms timer has run.
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!seen.contains(RideStatus.driverAssigned) &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(seen, contains(RideStatus.driverAssigned));
  });
}
