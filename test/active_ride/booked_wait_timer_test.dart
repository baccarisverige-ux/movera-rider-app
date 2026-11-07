import 'package:flutter/material.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/contracts/wire_time.dart';
import 'package:movera_rider/core/realtime/api_ride_realtime.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_fee_counter.dart';
import 'package:movera_rider/features/driver_arriving/application/driver_tracking_controller.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Contract v0.18.51 §73 (owner 2026-11-07, booked waiting): booked 08:00,
/// free 15 min, the driver arrives at 07:48. The rider's timer counts DOWN
/// to the pickup time (−12:00, "Before the pickup time"), then the free
/// minutes from 08:00, then the paid waiting. It said "16:00 free left" at
/// 07:59 and "Waiting 5:00 past the free 27 min" at 08:20 (free counted
/// from Arrived).
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  final arrived = DateTime(2026, 11, 7, 7, 48);
  final pickup = DateTime(2026, 11, 7, 8);
  final freeUntil = DateTime(2026, 11, 7, 8, 15);

  Future<void> pump(WidgetTester tester, DateTime now, {DateTime? waitFrom}) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WaitingFeeCounter(
              since: arrived,
              freeWaitMin: 15,
              perMin: const Money(500, 'SEK'),
              freeUntil: freeUntil,
              waitFrom: waitFrom,
              clock: () => now,
            ),
          ),
        ),
      );

  for (final waitFrom in [pickup, null]) {
    final how = waitFrom == null ? 'freeUntil only' : 'waitFrom';
    testWidgets('$how: early driver: −12:00 before the pickup time', (
      tester,
    ) async {
      await pump(tester, arrived, waitFrom: waitFrom);
      expect(find.text('−12:00'), findsOneWidget);
      expect(find.text(L10n.current.waitingBeforePickup), findsOneWidget);
    });

    testWidgets('$how: at the pickup time the 15 free minutes run', (
      tester,
    ) async {
      await pump(tester, pickup, waitFrom: waitFrom);
      expect(find.text(L10n.current.freeWaitingLeft('15:00')), findsOneWidget);
    });

    testWidgets('$how: 08:20 is 5:00 past the free 15 min', (tester) async {
      await pump(tester, DateTime(2026, 11, 7, 8, 20), waitFrom: waitFrom);
      expect(
        find.text(L10n.current.waitingTimeOverFree('5:00', '15')),
        findsOneWidget,
      );
    });
  }

  test('a late driver: the clock runs from his Arrived', () {
    final late = DateTime(2026, 11, 7, 8, 7);
    expect(
      DriverTrackingController.waitFromOf(
        arrivedAt: late,
        bookedPickupAt: pickup,
      ),
      late,
    );
    expect(
      DriverTrackingController.waitFromOf(
        arrivedAt: arrived,
        bookedPickupAt: pickup,
      ),
      pickup,
    );
    expect(
      DriverTrackingController.waitFromOf(arrivedAt: arrived),
      isNull,
      reason: 'a live ride keeps Arrived',
    );
    final server = DateTime(2026, 11, 7, 8, 1);
    expect(
      DriverTrackingController.waitFromOf(
        waitFrom: server,
        arrivedAt: arrived,
        bookedPickupAt: pickup,
      ),
      server,
    );
  });

  test(
    'waiting.waitFrom and a booked ride\'s scheduledAt reach the app',
    () async {
      final server = InProcessMockClient();
      final api = ApiClient(client: server);
      final id = await _book(api);
      await api.post('/api/v1/rides/$id/status', body: {'status': 'arrived'});
      final ride = server.rides[id]!;
      (ride['waiting'] as Map)['waitFrom'] = '2026-11-07T08:00:00Z';
      ride['kind'] = 'scheduled';
      ride['scheduledAt'] = '2026-11-07T08:00:00Z';
      final realtime = ApiRideRealtime(
        api: api,
        pollInterval: const Duration(days: 1),
      );
      addTearDown(realtime.dispose);
      final events = <RideRealtimeEvent>[];
      final sub = realtime.subscribe(id).listen(events.add);
      addTearDown(sub.cancel);
      await realtime.reconnectAndResync(id);
      for (var i = 0; i < 200 && events.isEmpty; i++) {
        await pumpEventQueue();
      }
      expect(events, isNotEmpty);
      final at = WireTime.tryParse('2026-11-07T08:00:00Z');
      expect(events.last.waitingWaitFrom, at);
      expect(events.last.bookedPickupAt, at);
    },
  );
}

Future<String> _book(ApiClient api) async {
  const at = {
    'pickupLat': 59.3293,
    'pickupLng': 18.0686,
    'destinationLat': 59.3326,
    'destinationLng': 18.0649,
  };
  final quote =
      (await api.post(
            '/api/v1/quotes',
            body: {'rideType': 'economy', ...at},
          ))['quote']
          as Map;
  final created = await api.post(
    '/api/v1/rides',
    body: {
      'categoryId': 'economy',
      'fare': {'amountMinor': quote['totalMinor'], 'currency': 'SEK'},
      'paymentMethodId': 'card',
      'pickupAddress': 'Pickup',
      'destinationAddress': 'Destination',
      ...at,
      'quoteId': quote['id'],
      'quoteSignedPayload': quote['signedPayload'],
      'quoteExpiresAt': quote['expiresAt'],
      'quoteTotalMinor': quote['totalMinor'],
    },
  );
  return (created['ride'] as Map)['id'] as String;
}
