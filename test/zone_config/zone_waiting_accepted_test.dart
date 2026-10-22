import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/config/rider_app_config.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/contracts/wire_time.dart';
import 'package:movera_rider/core/realtime/api_ride_realtime.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_fee_counter.dart';
import 'package:movera_rider/features/driver_arriving/application/driver_tracking_controller.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';

import 'zone_config_fakes.dart';

class _Feed implements RideRealtime {
  final events = StreamController<RideRealtimeEvent>.broadcast();

  @override
  bool get supportsRiderSignals => false;

  @override
  Stream<RideRealtimeEvent> subscribe(String rideId) => events.stream;

  @override
  Future<void> reconnectAndResync(String rideId) async {}

  @override
  Future<void> sendSignal({
    required String rideId,
    required RideRealtimeSignal signal,
    String? message,
  }) async {}

  @override
  void unsubscribe() {}

  @override
  void cancelRide() {}

  @override
  void researchAfterDriverCancel() {}

  @override
  void dispose() => unawaited(events.close());
}

/// Owner Q12: the free-cancel clock counts from the driver's accept
/// (`TripProjection.acceptedAt`). Q41/Q42: after the category's free wait
/// the rider sees a live waiting-fee counter at its per-minute rate.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('acceptedAt (Q12)', () {
    late InProcessMockClient server;
    late ApiClient api;

    setUp(() {
      server = InProcessMockClient();
      api = ApiClient(client: server);
    });

    Future<String> book() async {
      final quote = (await api.post(
        '/api/v1/quotes',
        body: {
          'rideType': 'economy',
          'pickupLat': 59.3293,
          'pickupLng': 18.0686,
          'destinationLat': 59.3326,
          'destinationLng': 18.0649,
        },
      ))['quote'] as Map;
      final created = await api.post(
        '/api/v1/rides',
        body: {
          'categoryId': 'economy',
          'fare': {'amountMinor': quote['totalMinor'], 'currency': 'SEK'},
          'paymentMethodId': 'card',
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
      return (created['ride'] as Map)['id'] as String;
    }

    Future<void> simulate(String id, Map<String, dynamic> body) =>
        api.post('/api/v1/rides/$id/status', body: body);

    test('the demo server stamps acceptedAt, and clears it on a new search',
        () async {
      final id = await book();
      expect(server.rides[id]!.containsKey('acceptedAt'), isTrue);
      expect(server.rides[id]!['acceptedAt'], isNull);

      await simulate(id, {'status': 'accepted'});
      final accepted = WireTime.tryParse(server.rides[id]!['acceptedAt']);
      expect(accepted, isNotNull);
      expect(DateTime.now().toUtc().difference(accepted!).inSeconds, lessThan(5));

      // The driver drops the trip: back to searching, no accept yet.
      await simulate(id, {'command': 'cancel', 'actor': 'driver'});
      expect(server.rides[id]!['status'], 'searching');
      expect(server.rides[id]!['acceptedAt'], isNull);
    });

    test('arrival starts the waiting clock with the category free wait',
        () async {
      final id = await book();
      await simulate(id, {'status': 'arrived'});
      final waiting = server.rides[id]!['waiting'] as Map;
      final arrived = WireTime.tryParse(waiting['arrivedAt'])!;
      final freeUntil = WireTime.tryParse(waiting['freeUntil'])!;
      expect(freeUntil.difference(arrived), const Duration(minutes: 5));
    });

    test('the rider app reads acceptedAt off the polled projection', () async {
      final id = await book();
      final realtime = ApiRideRealtime(
        api: api,
        pollInterval: const Duration(days: 1),
      );
      addTearDown(realtime.dispose);
      final events = <RideRealtimeEvent>[];
      final sub = realtime.subscribe(id).listen(events.add);
      addTearDown(sub.cancel);
      await Future<void>.delayed(Duration.zero);
      await simulate(id, {'status': 'arrived'});
      await realtime.reconnectAndResync(id);
      await Future<void>.delayed(Duration.zero);

      final last = events.last;
      expect(last.acceptedAt, WireTime.tryParse(server.rides[id]!['acceptedAt']));
      expect(
        last.waitingArrivedAt,
        WireTime.tryParse((server.rides[id]!['waiting'] as Map)['arrivedAt']),
      );
    });

    test('tracking keeps the server accept time, else none', () async {
      final feed = _Feed();
      addTearDown(feed.dispose);
      final tracking = DriverTrackingController(
        realtime: feed,
        pickupLat: 59.33,
        pickupLng: 18.06,
        persistRideSnapshot: false,
      );
      tracking.start(rideId: 'r1');
      final acceptedAt = DateTime.utc(2026, 10, 20, 8, 0, 0);

      feed.events.add(RideRealtimeEvent(
        tripId: 'r1',
        status: RideStatus.driverAssigned,
        sequence: 1,
        payload: {acceptedAtKey: WireTime.format(acceptedAt)},
      ));
      await Future<void>.delayed(Duration.zero);
      expect(tracking.acceptedAt, acceptedAt);

      // A later event without it keeps the accept time.
      feed.events.add(RideRealtimeEvent(
        tripId: 'r1',
        status: RideStatus.driverWaiting,
        sequence: 2,
      ));
      await Future<void>.delayed(Duration.zero);
      expect(tracking.acceptedAt, acceptedAt);
      expect(tracking.waitingSince, isNotNull);

      // The driver dropped the trip: both clocks start again later.
      feed.events.add(RideRealtimeEvent(
        tripId: 'r1',
        status: RideStatus.cancelledByDriver,
        sequence: 3,
      ));
      await Future<void>.delayed(Duration.zero);
      expect(tracking.acceptedAt, isNull);
      expect(tracking.waitingSince, isNull);
      tracking.dispose();
    });

    test('the free-cancel preview counts from acceptedAt', () {
      final config = SeedRiderConfigRepository.seed;
      final rule = config.liveFeeFor('economy')!;
      final acceptedAt = DateTime.utc(2026, 10, 20, 8);
      final preview = LiveCancelFeePreview.of(
        config,
        categoryId: 'economy',
        fare: const Money(25900, 'SEK'),
        acceptedAt: acceptedAt,
        now: acceptedAt.add(const Duration(minutes: 1)),
      )!;
      expect(preview.freeMinutesLeft, rule.freeMin - 1);
    });
  });

  group('waiting fee (Q42)', () {
    final since = DateTime.utc(2026, 10, 20, 9);

    test('free first, then the per-minute rate counted by the second', () {
      const rate = Money(500, 'SEK');
      var state = WaitingFeeState.at(
        since: since,
        now: since.add(const Duration(minutes: 3)),
        freeWaitMin: 5,
        perMin: rate,
      );
      expect(state.charging, isFalse);
      expect(state.freeLeft, const Duration(minutes: 2));
      expect(state.fee, const Money(0, 'SEK'));

      state = WaitingFeeState.at(
        since: since,
        now: since.add(const Duration(minutes: 8, seconds: 30)),
        freeWaitMin: 5,
        perMin: rate,
      );
      expect(state.charging, isTrue);
      expect(state.over, const Duration(minutes: 3, seconds: 30));
      expect(state.fee, const Money(1750, 'SEK'));
    });

    testWidgets('the counter runs live and shows the zone currency', (
      tester,
    ) async {
      var now = since.add(const Duration(minutes: 1));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WaitingFeeCounter(
              since: since,
              freeWaitMin: 3,
              perMin: const Money(115, 'EUR'),
              clock: () => now,
            ),
          ),
        ),
      );
      expect(find.text('Free waiting · 2:00 left'), findsOneWidget);
      expect(find.text('Then 1,15 €/min waiting fee'), findsOneWidget);

      now = since.add(const Duration(minutes: 6, seconds: 5));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Waiting fee 3,55 €'), findsOneWidget);
      expect(find.text('3:05 after the free 3 min · 1,15 €/min'), findsOneWidget);
    });

    test('each category has its own free wait and rate', () async {
      final config = await EditedZoneConfigs({
        'TN-TC': {
          'waiting': {
            'freeWaitMin': 5,
            'perMin': wireMoney(3700, 'TND'),
            'noShowAfterMin': 5,
            'noShowFee': wireMoney(19500, 'TND'),
            'byCategory': {
              'xl': {'freeWaitMin': 3, 'perMin': wireMoney(5000, 'TND')},
            },
          },
        },
      }).forZone('TN-TC');
      final economy = config.waiting!.forCategory('economy');
      final xl = config.waiting!.forCategory('xl');
      expect(economy.freeWaitMin, 5);
      expect(economy.perMin, const Money(3700, 'TND'));
      expect(xl.freeWaitMin, 3);
      expect(xl.perMin, const Money(5000, 'TND'));
    });
  });
}
